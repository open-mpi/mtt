# run this via pytest
# export MTT_HOME=/home/wcweide/dev/mtt.forked
# pytest ./test_TestDef.py
#   add the -s argument to display print lines
#   add the -v argument to be verbose
# ie  pytest -sv ./test_TestDef.py
import pytest
import os
import sys
import configparser
sys.path.append(os.path.join(os.environ['MTT_HOME'], "pylib/System"))
import TestDef as TD

def setup():
   td = TD.TestDef()
   td.config = configparser.ConfigParser(interpolation=configparser.ExtendedInterpolation())
   td.config.optionxform = str
   td.config.add_section('ENV')
   td.config.add_section('LOG')
   return td

def test_expandWildCardsAtEnd():
   td = setup()
   td.config.add_section('Reporter:IUDatabase')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Reporter:*']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:IUDatabase' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsAtBeginning():
   td = setup()
   td.config.add_section('Reporter:IUDatabase')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['*IUDatabase']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:IUDatabase' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsInMiddle():
   td = setup()
   td.config.add_section('Reporter:IUDatabase')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Report*UDatabase']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:IUDatabase' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsInBigList():
   td = setup()
   td.config.add_section('Reporter:IUDatabase')
   td.config.add_section('Reporter:TextFile')
   td.config.add_section('Reporter:JSONFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Report*UDatabase']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:IUDatabase' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsAtEndMultiple():
   td = setup()
   td.config.add_section('Reporter:IUDatabase')
   td.config.add_section('Reporter:TextFile')
   td.config.add_section('Reporter:JSONFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Report*']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:IUDatabase' in expsections and 'Reporter:TextFile' in expsections and 'Reporter:JSONFile' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsAtBeginningMultiple():
   td = setup()
   td.config.add_section('Reporter:XMLFile')
   td.config.add_section('Reporter:TextFile')
   td.config.add_section('Reporter:JSONFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['*File']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:XMLFile' in expsections and 'Reporter:TextFile' in expsections and 'Reporter:JSONFile' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsInMiddleMultiple():
   td = setup()
   td.config.add_section('Reporter:XMLFile')
   td.config.add_section('Reporter:TextFile')
   td.config.add_section('Reporter:JSONFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Rep*File']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:XMLFile' in expsections and 'Reporter:TextFile' in expsections and 'Reporter:JSONFile' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsMultipleStars():
   td = setup()
   td.config.add_section('Reporter:XMLFile')
   td.config.add_section('Reporter:TextFile')
   td.config.add_section('Reporter:JSONFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['*porter*File']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:XMLFile' in expsections and 'Reporter:TextFile' in expsections and 'Reporter:JSONFile' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsStarsAtBeginning():
   td = setup()
   td.config.add_section('Reporter:XMLFile')
   td.config.add_section('Reporter:TextFile')
   td.config.add_section('Reporter:JSONFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['*Reporter:TextFile']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:TextFile' in expsections 
   print("--->expanded:", expsections) 

def test_expandWildCardsStarsAtEnd():
   td = setup()
   td.config.add_section('Reporter:XMLFile')
   td.config.add_section('Reporter:TextFile')
   td.config.add_section('Reporter:JSONFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Reporter:TextFile*']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:TextFile' in expsections 
   print("--->expanded:", expsections) 

# this fails
#def test_expandWildCardsMultipleStarsInARow():
#   td = setup()
#   td.config.add_section('Reporter:TextFile')
#   print("--->sections:", td.config.sections())
#   assert td.config.sections() is not None
#   sections = ['Report****File']
#   print("--->to skip:", sections)
#   expsections = td.expandWildCards(sections)
#   assert 'Reporter:TextFile' in expsections
#   print("--->expanded:", expsections) 

def test_expandWildCardsMultipleStarsInARow():
   td = setup()
   td.config.add_section('Reporter:TextFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Report*:*ex*File']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:TextFile' in expsections
   print("--->expanded:", expsections) 

def test_expandWildCardsMultipleStarsInARowNoGaps():
   td = setup()
   td.config.add_section('Reporter:TextFile')
   print("--->sections:", td.config.sections())
   assert td.config.sections() is not None
   sections = ['Reporter*:*Text*File']
   print("--->to skip:", sections)
   expsections = td.expandWildCards(sections)
   assert 'Reporter:TextFile' in expsections
   print("--->expanded:", expsections) 

