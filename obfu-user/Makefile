#  To help obfuscate a user's information in omp database. Actual changes are to
#  be done by executing the generated SQL file(s).

path= /export/data/agarwal/home/src/jac-git/omp-perl/obfu-user

name_addr_list=  $(path)/list-sorted-name-addr

sanity_check=         $(path)/00.sanity-check-name-email.pl
sanity_check_id_out=  00.sanity-check-name-email-USERID.CSV
sanity_check_mis_out=  00.sanity-check-name-email-MISMATCH

update_addr_sql=  $(path)/01.update-addr-sql-for-edited.pl
update_addr_out=  01.update-addr-sql-for-edited-SQL

collect_userid=      $(path)/02.collect-userid.sh
collect_userid_out=  02.collect-userid--USERID-ONLY
inject_csv=          00.inject-name-email-userid.csv

obfuscate_sql=      $(path)/03.obfu-user-sql.pl
obfuscate_sql_out=  03.obfu-user-sql.SQL


most: obfuscate

all: update-addr obfuscate

noempty:
	find ./ -type f -empty -print0 | xargs -0 rm -fv

clean:
	rm -f \
        $(sanity_check_id_out) $(sanity_check_mis_out) \
        $(update_addr_out) \
        $(collect_userid_out) \
        $(obfuscate_sql_out)

sanity-check:
	cd $(path) || exit
	$(sanity_check) $(name_addr_list)

update-addr: sanity-check
	$(update_addr_sql) $(sanity_check_id_out) > $(update_addr_out)

userid-list: sanity-check
	$(collect_userid) $(sanity_check_id_out) $(inject_csv)

obfuscate: userid-list
	$(obfuscate_sql) $(collect_userid_out) >| $(obfuscate_sql_out)

