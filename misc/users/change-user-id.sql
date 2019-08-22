-- Replace an OMP user id with another

SET @remove = 'OLD_USER_ID';
SET @keep   = 'NEW_USER_ID';

UPDATE omp.ompfaultbody SET author        = @keep WHERE author        = @remove;
UPDATE omp.ompfeedback  SET author        = @keep WHERE author        = @remove;
UPDATE omp.ompshiftlog  SET author        = @keep WHERE author        = @remove;
UPDATE omp.ompobslog    SET commentauthor = @keep WHERE commentauthor = @remove;
UPDATE omp.ompproj      SET pi            = @keep WHERE pi            = @remove;
UPDATE omp.ompmsbdone   SET userid        = @keep WHERE userid        = @remove;
UPDATE omp.ompprojuser  SET userid        = @keep WHERE userid        = @remove;

-- To rename a user:
-- UPDATE omp.ompuser      SET userid        = @keep WHERE userid        = @remove;

-- To delete the old one (when merging records):
-- DELETE FROM omp.ompuser                           WHERE userid        = @remove;
