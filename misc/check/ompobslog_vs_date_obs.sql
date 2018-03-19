-- This query searches for ompobslog entries where the date doesn't match the
-- date_obs in the COMMON table.  Such values are problematic because comment
-- searches are performed by date, so they may not be found.

select
    jcmt.COMMON.obsid, jcmt.COMMON.date_obs, omp.ompobslog.date,
        jcmt.COMMON.date_obs - omp.ompobslog.date,
        omp.ompobslog.commentdate, jcmt.COMMON.last_modified
    from jcmt.COMMON join omp.ompobslog on jcmt.COMMON.obsid=omp.ompobslog.obsid
    where jcmt.COMMON.date_obs <> omp.ompobslog.date
    order by jcmt.COMMON.date_obs asc;
