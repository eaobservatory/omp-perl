# This directory contains the JCMT Translator test suite.
#
# The files comprise:
#
#     *-ot.xml          OT XML files describing observations.
#
#     *-reference.xml.N Reference translated OCS configuration file.
#                       (All XML files concatenated and without comments.)
#
# Additionally testing creates:
#
#     *-translated.xml   Manifest of translated files.
#
#     *-translated.xml.N OCS configuration translated from the OT XML files.
#
#     *.diff, *.diff.N   Differences between the reference and translated files.
#
# To clean up the directory, translate and check all of the OT XML files:
#
#     make clean
#     make
#
# Or as individual steps:
#
#     make translate
#     make diff
#     make report
#
# If all of the differences are intentional, update the reference files:
#
#     make updatereference
#     (and commit them to the Git repository)

.PHONY: default translate diff report updatereference clean

default: report

PID:=$(shell echo $$PPID)
PERL=perl -I .. -I ../../perl-JAC-OCS-Config/lib
TRANSLATOR=$(PERL) ../client/jcmttranslator.pl -cwd

OTXML=$(wildcard *-ot.xml)
TRANS=$(subst -ot.xml,-translated.xml,$(OTXML))
DIFF=$(subst -ot.xml,.diff,$(OTXML))

translate: $(TRANS)

diff: $(DIFF)

report: $(DIFF)
	cat $(DIFF)

updatereference:
	for file in *-translated.xml.*; do \
	  cp $$file $${file/-translated/-reference} ;\
	done

clean:
	rm -f *-translated.xml *-translated.xml.* *.diff *.diff.* *.manifest

%.diff: %-translated.xml
	echo -n > $@
	for file in $<.*; do \
	  difffile=$${file/-translated.xml/.diff} ;\
	  diff $${file/-translated/-reference} $$file > $$difffile || cat $$difffile ;\
	  wc -l $$difffile >> $@ ;\
	done

%-translated.xml: %-ot.xml
	$(TRANSLATOR) $< > $(PID).manifest
	mv $$(< $(PID).manifest) $@
	rm $(PID).manifest
	
	n=0 ;\
	for file in `sed -n -e 's/ *<\/\?Entry[^>]*>//gp' $@` ; do \
	    n=$$(( n + 1 )) ;\
	    perl strip-xml.pl < $$file > $@.$$n ;\
	    rm $$file ;\
	  done ;\
