.PHONY: default test

default: test

test: PASSWORD.pm
	perl run-tests.pl

PASSWORD.pm: PASSWORD.template
	touch $@
	chmod 600 $@
	read -s -p "Staff password: " STAFFPASS ; \
	sed -e "s/__STAFFPASSWORD__/$${STAFFPASS}/" $^ >> $@
