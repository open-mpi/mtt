# allow the use of fixture functions
# 
import pytest
class myClass(object):
    def __init__(self, f):
        self.f = f

    def __call__(self):
        self.f()


def func(x):
    return x + 1

def test_answer():
    assert func(3) == 4

def test_one(foo, bar):
    pass

def test_two(foo, bar):
    pass
        

# now can use
# @myClass
# to call a function



    
    
