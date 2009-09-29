# -*- coding: utf-8 -*-
"""
    tipfy.model.pager
    ~~~~~~~~~~~~~~~~~

    Universal pagination class for App Engine models. Supports "efficient paging
    in any query, on any schema, purely in user land, without requiring extra
    properties or other schema changes". This means that no property is
    required to be used as index, and that it can easily build efficient
    pagination for any existing model or query.

    PagerQuery wraps and has the same interface as db.Query, except that fetch()
    takes a bookmark parameter instead of an offset. The query returns results
    and bookmarks for the next or previous results, if available.

    A bookmark is the first or last result entity that was returned to the app
    for a given query, serialized and base64-encoded so that apps can pass it
    around in URL parameters, cookies, etc.

    It is based on the concept posted in the App Engine group:
    http://google-appengine.googlegroups.com/web/efficient_paging_using_key_instead_of_a_dedicated_unique_property.txt

    Quick example:

    # Get the encoded bookmark from request.
    bookmark = request.GET['bookmark']

    # Build a paginated query.
    query = PagerQuery(ModelClass).filter('foo >', 'bar') \
                                  .filter('baz =', 'ding') \
                                  .order('foo')

    # Fetch results for the current page and bookmarks for previous and next
    # pages.
    prev, results, next = query.fetch(10, bookmark)

    # For a searchable query, use:
    query = SearchablePagerQuery(ModelClass).filter('foo >', 'bar') \
                                            .filter('baz =', 'ding') \
                                            .order('foo') \
                                            .search('my_string')

    prev, results, next = query.fetch(10, bookmark)

    # If 'prev' and/or 'next' are returned, use them to create links to the
    # previous and/or next pages.
    http://localhost:8080/?bookmark={{ prev }}
    http://localhost:8080/?bookmark={{ next }}

    :copyright: 2009 by tipfy.org.
    :license: BSD, see LICENSE.txt for more details.
"""
import re
from base64 import b64encode, b64decode
from urllib import urlencode
from cgi import parse_qsl
from datetime import datetime

from google.appengine.ext import db
from google.appengine.ext.search import SearchableQuery, SearchableMultiQuery
from google.appengine.api import datastore_errors

# Regex borrowed from google.appengine.api.datastore.
OPERATORS = ['<', '<=', '>', '>=', '=', '==']
INEQUALITY_OPERATORS = ['<', '<=', '>', '>=']
FILTER_REGEX = re.compile(
    '^\s*([^\s]+)(\s+(%s)\s*)?$' % '|'.join(OPERATORS),
    re.IGNORECASE | re.UNICODE)

def match_filter(prop_operator):
    """Returns the property and operator given a value passed to filter()."""
    matches = FILTER_REGEX.match(prop_operator)
    return (matches.group(1), matches.group(3))

def encode_bookmark(values):
    """Encodes a dictionary into a string."""
    return b64encode(urlencode(values))

def decode_bookmark(bookmark):
    """Decodes a string into a bookmark dictionary."""
    return dict(parse_qsl(b64decode(bookmark)))

class PagerQuery(object):
    """Wraps db.Query to build bookmarkable queries, and to resume queries from
    bookmarks.
    """
    query_class = db.Query

    def __init__(self, model_class, keys_only=False):
        """Constructs a bookmarkable query over instances of the given Model.

        Args:
          model_class: Model class to build query for.
          keys_only: Whether the query should return full entities or only keys.
        """
        # Initialize query values.
        self._model_class = model_class
        self._keys_only = keys_only
        self._ancestor = None
        self._filters = {}
        self._inequality_prop = None
        self._inequality_filters = {}
        self._orderings = []
        self._order_directions = {}
        # Properties that should be encoded into a bookmark: inequalities
        # and orderings.
        self._bookmark_properties = []
        # Keep track of first result to know when we are on first page.
        self._first_result = None

    def filter(self, property_operator, value):
        """Adds a filter to query.

        Args:
          property_operator: string with the property and operator to filter by.
          value: the filter value.

        Returns:
          Self to support method chaining.

        Raises:
          BadArgumentError if invalid property is provided or two different
          inequality properties are set for the same query.
        """
        prop, operator = match_filter(property_operator)
        if operator in INEQUALITY_OPERATORS:
            if self._inequality_prop and self._inequality_prop != prop:
                raise datastore_errors.BadArgumentError('Queries must have '
                    'only one inequality operator.')
            self._inequality_prop = prop
            self._inequality_filters[operator] = value

            # Store the property name to be used in bookmarks.
            if prop not in self._bookmark_properties:
                self._bookmark_properties.append(prop)
        elif operator in OPERATORS:
            self._filters[prop] = value
        else:
            raise datastore_errors.BadArgumentError('Filter operator is not '
                'valid, received %s.' % operator)
        return self

    def order(self, prop):
        """Sets order of query result.

        To use descending order, prepend '-' (minus) to the property
        name, e.g., '-date' rather than 'date'.

        Args:
          property: Property to sort on.

        Returns:
          Self to support method chaining.
        """
        direction = ''
        if prop.startswith('-'):
            prop = prop[1:]
            direction = '-'
        self._orderings.append(prop)
        self._order_directions[prop] = direction

        # Store the property name to be used in bookmarks.
        if prop not in self._bookmark_properties:
            self._bookmark_properties.append(prop)
        return self

    def ancestor(self, ancestor):
        """Sets an ancestor for this query.

        This restricts the query to only return results that descend from
        a given model instance. In other words, all of the results will
        have the ancestor as their parent, or parent's parent, etc.  The
        ancestor itself is also a possible result!

        Args:
          ancestor: Model or Key (that has already been saved)

        Returns:
          Self to support method chaining.
        """
        self._ancestor = ancestor
        return self

    def fetch(self, limit, bookmark=None):
        """Fetches the query results, returning bookmarks for next and previous
        pages if available. If bookmark is provided, the query is resumed from
        that bookmark.

        Args:
          limit: Maximum number of results to return.
          bookmark: Encoded values of the query to be resumed.

        Returns:
          A tuple (prev, res, next), where 'prev' and 'next' are bookmarks
          for the next and previous pages and 'res' is a list of db.Model
          instances for the current page.
        """
        # If the query has an inequality filter but no sort order:
        # appends an ASC sort order on the inequality property.
        if self._inequality_prop and not self._orderings:
            self.order(self._inequality_prop)

        # If the query doesn't have a sort order on __key__:
        # append an ASC sort order on __key__.
        if '__key__' not in self._orderings:
            self.order('__key__')

        reverse = False
        if bookmark:
            # Resume the query from this bookmark.
            # For reversed queries, invert all orderings.
            if bookmark.startswith('-'):
                reverse = True
                bookmark = bookmark[1:]

                directions = {'': '-', '-': ''}
                for prop, direction in self._order_directions.iteritems():
                    self._order_directions[prop] = directions[direction]

            res = self._fetch_from_bookmark(limit + 1, bookmark)
        else:
            # Fetch bookmarkable results.
            query = self._get_query(filters=self._filters,
                inequality_prop=self._inequality_prop,
                inequality_filters=self._inequality_filters,
                orderings=self._orderings,
                order_directions=self._order_directions)
            res = query.fetch(limit + 1)

        # Build the next and previous bookmarks.
        prev = None
        next = None
        if res:
            has_prev = False
            has_next = False

            # Prepare results, removing excedent and reversing if needed.
            if len(res) > limit:
                res.pop()
                has_next = True

            if reverse:
                res.reverse()

            # Track the very first result to avoid building the 'previous'
            # bookmark for the first page.
            first_result_key = str(res[0].key().id_or_name())
            if not bookmark:
                self._first_result = first_result_key
            elif self._first_result and self._first_result != first_result_key:
                # Only show previous link if this is not the first page.
                has_prev = True

            # Build the 'next' bookmark using the last result.
            if reverse or has_next:
                next = encode_bookmark(self._get_bookmark_values(res[-1]))

            # Build the 'previous' bookmark using the first result.
            if bookmark and has_prev:
                prev = '-' + encode_bookmark(self._get_bookmark_values(res[0]))

        return (prev, res, next)

    def _fetch_from_bookmark(self, limit, bookmark):
        """Fetches results resuming a query from a bookmark. This may require
        additional queries depending on the number of sort orders.

        Args:
          limit: Maximum number of results to return.
          bookmark: Encoded values of the query to be resumed.

        Returns:
          A list of db.Model instances.  There may be fewer than 'limit'
          results if there aren't enough results to satisfy the request.
        """
        bookmark = self._decode_bookmark(bookmark)
        if  not bookmark:
            return []

        # Add a new filter to the query: "prop = [bookmark value for prop]"
        q_filters = dict(self._filters)
        for prop in self._orderings:
            q_filters[prop] = bookmark[prop]

        # Build the derived queries starting from bookmark.
        queries = []
        q_orderings = []
        q_order_directions = {}
        self._orderings.reverse()
        for prop in self._orderings:
            # Add order on prop to the beginning of the list.
            q_orderings.insert(0, prop)
            q_order_directions[prop] = self._order_directions[prop]

            # Replace the = filter on prop by a inequality one.
            q_filters.pop(prop)
            if q_order_directions[prop] == '':
                operator = '>'
            else:
                operator = '<'
            q_inequality_filters = {operator: bookmark[prop]}

            # If there are more inequality filters on prop, add them.
            if prop == self._inequality_prop:
                for operator, val in self._inequality_filters.iteritems():
                    if operator not in q_inequality_filters:
                        q_inequality_filters[operator] = val

            query = self._get_query(filters=q_filters, inequality_prop=prop,
                inequality_filters=q_inequality_filters, orderings=q_orderings,
                order_directions=q_order_directions)
            queries.append(query)

        # Fetch the results until reach limit.
        results = []
        for query in queries:
            results.extend(query.fetch(limit))
            limit -= len(results)
            if limit == 0:
                break

        return results

    def _get_query(self, filters={}, inequality_prop=None,
        inequality_filters={}, orderings=[], order_directions={}):
        """Builds a db.Query.

        Returns:
          A google.appengine.ext.db.Query instance.
        """
        query = self.__class__.query_class(self._model_class,
            keys_only=self._keys_only)

        if self._ancestor:
            query.ancestor(self._ancestor)

        if inequality_prop and inequality_filters:
            for operator, value in inequality_filters.iteritems():
                query.filter(inequality_prop + ' ' + operator, value)

        for prop, value in filters.iteritems():
            query.filter(prop + ' =', value)

        for prop in orderings:
            query.order(order_directions[prop] + prop)

        return query

    def _get_bookmark_values(self, entity):
        """Returns a dictionary to build a bookmark. The properties used are
        the filter inequalities and the query sort orders, plus the entity key
        and the key_name or id of the very first result of the first page.

        Returns:
          A dictionary of property names/values to build a bookmark.
        """
        values = {}
        for prop in self._bookmark_properties:
            if prop == '__key__':
                values[prop] = entity.key()
            else:
                values[prop] = str(getattr(entity, prop))
        if self._first_result:
            values['_'] = self._first_result
        return values

    def _decode_bookmark(self, bookmark):
        """Decodes a bookmark and prepares the values to be used on queries.
        Currently supported properties are:
          DateProperty
          DateTimeProperty
          FloatProperty
          IntegerProperty
          StringProperty
          ReferenceProperty
          TimeProperty

        Returns:
          A dictionary of property names/values to be used in queries.
        """
        required = list(self._bookmark_properties)
        required.append('_')
        try:
            bookmark = decode_bookmark(bookmark)
            # Ensure that all required values are available.
            for key in required:
                if key not in bookmark:
                    return None
        except:
            return None

        for key in required:
            value = bookmark[key]
            if key == '_':
                self._first_result = bookmark[key]
            elif key == '__key__':
                bookmark[key] = db.Key(value)
            else:
                prop = getattr(self._model_class, key)
                if isinstance(prop, db.ReferenceProperty):
                    bookmark[key] = db.Key(value)
                elif isinstance(prop, db.DateProperty):
                    bookmark[key] = \
                        datetime.strptime(str(value), '%Y-%m-%d').date()
                elif isinstance(prop, db.TimeProperty):
                    bookmark[key] = parse_datetime(value, '%H:%M:%S').time()
                elif isinstance(prop, db.DateTimeProperty):
                    bookmark[key] = parse_datetime(value, '%Y-%m-%d %H:%M:%S')
                else:
                    bookmark[key] = prop.data_type(value)

        return bookmark


class SearchablePagerQuery(PagerQuery):
    class Query(db.Query):
        """A subclass of db.Query that supports full text search."""
        _search_query = None

        def search(self, search_query):
            """Adds a full text search to this query.

            Args:
              search_query, a string containing the full text search query.

            Returns:
              self
            """
            self._search_query = search_query
            return self

        def _get_query(self):
            """Wraps db.Query._get_query() and injects SearchableQuery."""
            query = db.Query._get_query(self,
                                  _query_class=SearchableQuery,
                                  _multi_query_class=SearchableMultiQuery)
            if self._search_query:
                query.Search(self._search_query)
            return query

    query_class = Query
    _search_query = None

    def search(self, search_query):
        self._search_query = search_query
        return self

    def _get_query(self, **kargs):
        query = super(SearchablePagerQuery, self)._get_query(**kargs)
        if self._search_query:
            query.search(self._search_query)
        return query


# borrowed from
# http://kbyanc.blogspot.com/2007/09/python-reconstructing-datetimes-from.html
def parse_datetime(s, format):
    """Create datetime object representing date/time
    expressed in a string.

    This is required because converting microseconds using strptime() is only
    supported in Python 2.6.

    Takes a string in the format produced by calling str()
    on a python datetime or time objects and returns a datetime
    instance that would produce that string.

    Acceptable formats are: "YYYY-MM-DD HH:MM:SS.ssssss+HH:MM",
                            "YYYY-MM-DD HH:MM:SS.ssssss",
                            "YYYY-MM-DD HH:MM:SS+HH:MM",
                            "YYYY-MM-DD HH:MM:SS"
    Where ssssss represents fractional seconds.	 The timezone
    is optional and may be either positive or negative
    hours/minutes east of UTC.
    """
    if s is None:
        return None
    # Split string in the form 2007-06-18 19:39:25.3300-07:00
    # into its constituent date/time, microseconds, and
    # timezone fields where microseconds and timezone are
    # optional.
    m = re.match(r'(.*?)(?:\.(\d+))?(([-+]\d{1,2}):(\d{2}))?$',
                 str(s))
    datestr, fractional, tzname, tzhour, tzmin = m.groups()

    # Create tzinfo object representing the timezone
    # expressed in the input string.  The names we give
    # for the timezones are lame: they are just the offset
    # from UTC (as it appeared in the input string).  We
    # handle UTC specially since it is a very common case
    # and we know its name.
    if tzname is None:
        tz = None
    else:
        tzhour, tzmin = int(tzhour), int(tzmin)
        if tzhour == tzmin == 0:
            tzname = 'UTC'
        tz = FixedOffset(timedelta(hours=tzhour,
                                   minutes=tzmin), tzname)

    # Convert the date/time field into a python datetime
    # object.
    x = datetime.strptime(datestr, format)

    # Convert the fractional second portion into a count
    # of microseconds.
    if fractional is None:
        fractional = '0'
    fracpower = 6 - len(fractional)
    fractional = float(fractional) * (10 ** fracpower)

    # Return updated datetime object with microseconds and
    # timezone information.
    return x.replace(microsecond=int(fractional), tzinfo=tz)
