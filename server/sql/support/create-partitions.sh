#
# This script just generates the partiion table files for 2006 - 2010
#
# It should be used as an example for how to run the generation scripts
# as we don't want to replace the existing partition tables going forward.
#
./create-partitions-mpi-install.pl 2006 11 >  2006-mpi-install.sql
./create-partitions-mpi-install.pl 2006 12 >> 2006-mpi-install.sql
./create-partitions-mpi-install.pl 2007 XX >  2007-mpi-install.sql
./create-partitions-mpi-install.pl 2008 XX >  2008-mpi-install.sql
./create-partitions-mpi-install.pl 2009 XX >  2009-mpi-install.sql
./create-partitions-mpi-install.pl 2010 XX >  2010-mpi-install.sql
./create-partitions-mpi-install.pl 2011 XX >  2011-mpi-install.sql

./create-partitions-test-build.pl 2006 11 >  2006-test-build.sql
./create-partitions-test-build.pl 2006 12 >> 2006-test-build.sql
./create-partitions-test-build.pl 2007 XX >  2007-test-build.sql
./create-partitions-test-build.pl 2008 XX >  2008-test-build.sql
./create-partitions-test-build.pl 2009 XX >  2009-test-build.sql
./create-partitions-test-build.pl 2010 XX >  2010-test-build.sql
./create-partitions-test-build.pl 2011 XX >  2011-test-build.sql

./create-partitions-test-run.pl 2006 11 >  2006-test-run.sql
./create-partitions-test-run.pl 2006 12 >> 2006-test-run.sql
./create-partitions-test-run.pl 2007 XX >  2007-test-run.sql
./create-partitions-test-run.pl 2008 XX >  2008-test-run.sql
./create-partitions-test-run.pl 2009 XX >  2009-test-run.sql
./create-partitions-test-run.pl 2010 XX >  2010-test-run.sql
./create-partitions-test-run.pl 2011 XX >  2011-test-run.sql

#
# Create the indexes for these partitions
#
./create-partition-indexes.pl 2006 11 >  2006-indexes.sql
./create-partition-indexes.pl 2006 12 >> 2006-indexes.sql
./create-partition-indexes.pl 2007 XX >  2007-indexes.sql
./create-partition-indexes.pl 2008 XX >  2008-indexes.sql
./create-partition-indexes.pl 2009 XX >  2009-indexes.sql
./create-partition-indexes.pl 2010 XX >  2010-indexes.sql
./create-partition-indexes.pl 2011 XX >  2011-indexes.sql
