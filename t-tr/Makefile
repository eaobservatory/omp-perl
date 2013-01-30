# This directory contains the JCMT Translator test suite.
#
# The files comprise:
#
#     *-ot.xml        OT XML files describing observations.
#
#     *-reference.xml Reference translated OCS configuration file.
#                     (All XML files concatenated and without comments.)
#
# Additionally testing creates:
#
#     *-translated.xml OCS configuration translated from the OT XML files.
#
#     *.diff           Differences between the reference and translated files.
#
# To clean up the directory and try to translate all of the OT XML files:
#
#     make clean
#     make test
#
# To compare them with the reference translations:
#
#     make diff
#
# If all of the differences are intentional, update the reference files:
#
#     make updatereference
#     (and commit them to the Git repository)

.PHONY: default test diff updatereference clean

default: test

PID:=$(shell echo $$PPID)
PERL=perl -I .. -I ../perl-JAC-OCS-Config/lib
TRANSLATOR=$(PERL) ../client/jcmttranslator.pl -cwd

OTXML=$(wildcard *-ot.xml)
TRANS=$(subst -ot.xml,-translated.xml,$(OTXML))
DIFF=$(subst -ot.xml,.diff,$(OTXML))

test: $(TRANS)

diff: $(DIFF)

updatereference:
	for file in *-translated.xml; do \
	  cp $$file $${file%-translated.xml}-reference.xml ;\
	done

clean:
	rm -f *-translated.xml *.diff

%.diff: %-reference.xml %-translated.xml
	diff $^ > $@ || cat $@

%-translated.xml: %-ot.xml
	$(TRANSLATOR) $< > $(PID).manifest
	echo -n > $@
	
	manifest=`cat $(PID).manifest` ;\
	for file in `sed -n -e 's/ *<\/\?Entry[^>]*>//gp' \
	    $$manifest`; do \
	    perl strip-xml.pl < $$file >> $@ ;\
	    rm $$file ;\
	  done ;\
	rm $$manifest
	
	rm $(PID).manifest
