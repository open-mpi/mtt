#
# This script just generates the partiion table files for 2006 and 2007
#
# It should be used as an example for how to run the generation scripts
# as we don't want to replace the existing partition tables going forward.
#
./create-partitions-mpi-install.pl 2006 11 >  2006-mpi-install.sql
./create-partitions-mpi-install.pl 2006 12 >> 2006-mpi-install.sql
./create-partitions-mpi-install.pl 2007 XX >  2007-mpi-install.sql

./create-partitions-test-build.pl 2006 11 >  2006-test-build.sql
./create-partitions-test-build.pl 2006 12 >> 2006-test-build.sql
./create-partitions-test-build.pl 2007 XX >  2007-test-build.sql

./create-partitions-test-run.pl 2006 11 >  2006-test-run.sql
./create-partitions-test-run.pl 2006 12 >> 2006-test-run.sql
./create-partitions-test-run.pl 2007 XX >  2007-test-run.sql

#
# Create the indexes for these partitions
#
./create-partition-indexes.pl 2006 11 >  2006-indexes.sql
./create-partition-indexes.pl 2006 12 >> 2006-indexes.sql
./create-partition-indexes.pl 2007 XX >  2007-indexes.sql
./create-partition-indexes.pl 2007 08  > 2007-indexes-aug.sql
