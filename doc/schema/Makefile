.PHONY: all clean

SCHEMAS=omp.sql jcmt.sql jcmt_tms.sql ukirt.sql

all: $(SCHEMAS)

SERVER=`perl -I ../../lib -MOMP::DBbackend::Archive -e 'my %lh = OMP::DBbackend::Archive->loginhash(); print $$lh{"server"}'`
USER=`perl -I ../../lib -MOMP::DBbackend::Archive -e 'my %lh = OMP::DBbackend::Archive->loginhash(); print $$lh{"user"}'`
PASSWORD=`perl -I ../../lib -MOMP::DBbackend::Archive -e 'my %lh = OMP::DBbackend::Archive->loginhash(); print $$lh{"password"}'`

%.sql: filter.sed
	mysqldump $(@:.sql=) -h $(SERVER) -d -u $(USER) --password=$(PASSWORD) --compact --single-transaction > $@.tmp
	sed -f filter.sed $@.tmp > $@
	rm $@.tmp

clean:
	rm -f $(SCHEMAS)
