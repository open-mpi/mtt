#!/usr/bin/env python
#
# Copyright (c) 2016-2018 Intel, Inc.  All rights reserved.
# $COPYRIGHT$
#
# Additional copyrights may follow
#
# $HEADER$
#

from __future__ import print_function
import os
from BaseMTTUtility import *

## @addtogroup Utilities
# @{
# @section Compilers
# @}
class Compilers(BaseMTTUtility):
    def __init__(self):
        BaseMTTUtility.__init__(self)
        self.options = {}
        return

    def print_name(self):
        return "Compilers"

    def print_options(self, testDef, prefix):
        lines = testDef.printOptions(self.options)
        for line in lines:
            print(prefix + line)
        return

    def execute(self, log, testDef):
        # GNU is probably the most common, so check that one as soon as
        # possible.  Intel pretends to be GNU, so need to check Intel
        # before checking for GNU.

        # Intel
        if self.check_c_if(testDef, "defined(__INTEL_COMPILER) || defined(__ICC)", "icc"):
            compiler = "intel"
            status, vsn = self.check_version("icc", "--version", testDef)
        # Pathscale
        elif self.check_c_ifdef(testDef, "__PATHSCALE__", "pgcc"):
            compiler = "pathscale"
            status, vsn = self.check_version("pgcc", "-V", testDef)
        # GNU
        elif self.check_c_ifdef(testDef, "__GNUC__", "gcc"):
            compiler = "gnu"
            status, vsn = self.check_version("gcc", "--version", testDef)
        # Borland Turbo C
        elif self.check_c_ifdef(testDef, "__TURBOC__", "tcc"):
            compiler = "borland"
            status, vsn = self.check_version("tcc", "--version", testDef)
        # Borland C++
        elif self.check_c_ifdef(testDef, "__BORLANDC__", "cpp"):
            compiler = "borland"
            status, vsn = self.check_version("cpp", "--version", testDef)
        # Compaq C/C++
        elif self.check_c_ifdef(testDef, "__COMO__", "cc"):
            compiler = "comeau"
            status, vsn = self.check_version("cc", "--version", testDef)
        elif self.check_c_if(testDef, "defined(__DECC) || defined(VAXC) || defined(__VAXC)", "cc"):
            compiler = "compaq"
            status, vsn = self.check_version("cc", "--version", testDef)
        elif self.check_c_if(testDef, "defined(__osf__) || defined(__LANGUAGE_C__)", "cc"):
            compiler = "compaq"
            status, vsn = self.check_version("cc", "--version", testDef)
        elif self.check_c_ifdef(testDef, "__DECCXX", "cc"):
            compiler = "compaq"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Cray C/C++
        elif self.check_c_ifdef(testDef, "_CRAYC", "cc"):
            compiler = "cray"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Diab C/C++
        elif self.check_c_ifdef(testDef, "__DCC", "cc"):
            compiler = "diab"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Digital Mars
        elif self.check_c_if(testDef, "defined(__DMC__) || defined(__SC__) || defined(__ZTC__)", "cc"):
            compiler = "digital mars"
            status, vsn = self.check_version("cc", "--version", testDef)
        # HP ANSI C / aC++
        elif self.check_c_if(testDef, "defined(__HP_cc) || defined(__HP_aCC)", "cc"):
            compiler = "hp"
            status, vsn = self.check_version("cc", "--version", testDef)
        # IBM XL C/C++
        elif self.check_c_if(testDef, "defined(__xlC__) || defined(__IBMC__) || defined(__IBMCPP__)", "cc"):
            compiler = "ibm"
            status, vsn = self.check_version("cc", "--version", testDef)
        # IBM XL C/C++
        elif self.check_c_if(testDef, "defined(_AIX) && defined(__GNUC__)", "cc"):
            compiler = "ibm"
            status, vsn = self.check_version("cc", "--version", testDef)
        # KAI C++ (rest in peace)
        elif self.check_c_ifdef(testDef, "__KCC", "cc"):
            compiler = "kai"
            status, vsn = self.check_version("cc", "--version", testDef)
        # LCC
        elif self.check_c_ifdef(testDef, "__LCC__", "cc"):
            compiler = "lcc"
            status, vsn = self.check_version("cc", "--version", testDef)
        # MetaWare High C/C++
        elif self.check_c_ifdef(testDef, "__HIGHC__", "cc"):
            compiler = "metaware high"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Metrowerks Codewarrior
        elif self.check_c_ifdef(testDef, "__MWERKS__", "cc"):
            compiler = "metrowerks"
            status, vsn = self.check_version("cc", "--version", testDef)
        # MIPSpro (SGI)
        elif self.check_c_if(testDef, "defined(sgi) || defined(__sgi)", "cc"):
            compiler = "sgi"
            status, vsn = self.check_version("cc", "--version", testDef)
        # MPW C++
        elif self.check_c_if(testDef, "defined(__MRC__) || defined(MPW_C) || defined(MPW_CPLUS)", "cpp"):
            compiler = "mpw"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Microsoft
        # (Always use C compiler when checking for Microsoft, as
        # Visual C++ doesn't recognize .cc as a C++ file.)
        elif self.check_c_if(testDef, "defined(_MSC_VER) || defined(__MSC_VER)", "cc"):
            compiler = "microsoft"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Norcroft C
        elif self.check_c_ifdef(testDef, "__CC_NORCROFT", "cc"):
            compiler = "norcroft"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Pelles C
        elif self.check_c_ifdef(testDef, "__POCC__", "cc"):
            compiler = "pelles"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Portland Group
        elif self.check_c_ifdef(testDef, "__PGI", "cc"):
            compiler = "pgi"
            status, vsn = self.check_version("cc", "--version", testDef)
        # SAS/C
        elif self.check_c_if(testDef, "defined(SASC) || defined(__SASC) || defined(__SASC__)", "cc"):
            compiler = "sas"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Sun Workshop C/C++
        elif self.check_c_if(testDef, "defined(__SUNPRO_C) || defined(__SUNPRO_CC)", "cc"):
            compiler = "sun"
            status, vsn = self.check_version("cc", "--version", testDef)
        # TenDRA C/C++
        elif self.check_c_ifdef(testDef, "__TenDRA__", "cc"):
            compiler = "tendra"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Tiny C
        elif self.check_c_ifdef(testDef, "__TINYC__", "cc"):
            compiler = "tiny"
            status, vsn = self.check_version("cc", "--version", testDef)
        # USL C
        elif self.check_c_ifdef(testDef, "__USLC__", "cc"):
            compiler = "usl"
            status, vsn = self.check_version("cc", "--version", testDef)
        # Watcom C++
        elif self.check_c_ifdef(testDef, "__WATCOMC__", "cpp"):
            compiler = "watcom"
            status, vsn = self.check_version("cpp", "--version", testDef)

        else:
            vsn = [""]
            status = 1;
            compiler = "None"
            version = "Unknown"
        # record the result
        log['status'] = status
        log['compiler'] = compiler
        log['version'] = vsn[0][:64]
        return

    def check_compile(self, testDef, macro, c_code, compiler):
        # write out a little test program
        fh = open("spastic.c", 'w')
        for ln in c_code:
            print(ln, file=fh)
        fh.close()

        # Attempt to compile it
        mycmdargs = [compiler, "-c", "spastic.c"]
        status, stdout, stderr, _ = testDef.execmd.execute(None, mycmdargs, testDef)

        # cleanup the test
        os.remove("spastic.c")
        if os.path.exists("spastic.o"):
            os.remove("spastic.o")

        if 0 == status:
            return True
        return False

    def check_c_ifdef(self, testDef, macro, compiler):

        c_code = ["/*", "* This program is automatically generated by compiler.py",
                  "* of MPI Testing Tool (MTT).  Any changes you make here may",
                  "* get lost!", "*",
                  "* Copyrights and licenses of this file are the same as for the MTT.",
                  "*/", "#ifndef " + macro, "#error", "choke me", "#endif"]

        return self.check_compile(testDef, macro, c_code, compiler);

    def check_c_if(self, testDef, macro, compiler):

        c_code = ["/*", "* This program is automatically generated by compiler.py",
                  "* of MPI Testing Tool (MTT).  Any changes you make here may",
                  "* get lost!", "*",
                  "* Copyrights and licenses of this file are the same as for the MTT.",
                  "*/", "#if !( " + macro + " )", "#error", "choke me", "#endif"]

        return self.check_compile(testDef, macro, c_code, compiler);

    def check_version(self, compiler, version, testDef):
        # try the universal version option
        mycmdargs = [compiler, version]
        status, stdout, stderr, _ = testDef.execmd.execute(None, mycmdargs, testDef)
        return status, stdout

