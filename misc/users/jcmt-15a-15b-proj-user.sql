
-- Generate list of 15[AB] JCMT project users for Graham to merge with Hedwig
-- user list, to be added as "JCMT_Users" Google Groups members.

SELECT  u.userid AS userid
      , u.email  AS email
      , u.uname  AS name
FROM  omp..ompuser u
WHERE u.userid IN
      ( SELECT pu.userid
        FROM  omp..ompproj p , omp..ompprojuser pu
        WHERE p.telescope = 'JCMT' AND p.semester IN ( '15A' , '15B' )
          AND p.projectid = pu.projectid
      )
ORDER BY u.name , u.userid

go

