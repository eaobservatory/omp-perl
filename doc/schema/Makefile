.PHONY: all clean

SCHEMAS=omp.sql jcmt.sql jcmt_tms.sql ukirt.sql

all: $(SCHEMAS)

export OMP_CFG_DIR=../../cfg
SERVER=`perl -I ../../lib -MOMP::DB::Backend::Archive -e 'my %lh = OMP::DB::Backend::Archive->loginhash(); print $$lh{"server"}'`
USER=`perl -I ../../lib -MOMP::DB::Backend::Archive -e 'my %lh = OMP::DB::Backend::Archive->loginhash(); print $$lh{"user"}'`
PASSWORD=`perl -I ../../lib -MOMP::DB::Backend::Archive -e 'my %lh = OMP::DB::Backend::Archive->loginhash(); print $$lh{"password"}'`
PREFIX=`perl -I ../../lib -MOMP::Config -e 'print OMP::Config->new()->getData("arc-database-prefix")'`

%.sql: filter.sed
	mysqldump $(PREFIX)$(@:.sql=) -h $(SERVER) -d -u $(USER) --password=$(PASSWORD) --compact --single-transaction > $@.tmp
	sed -f filter.sed $@.tmp > $@
	rm $@.tmp

clean:
	rm -f $(SCHEMAS)
