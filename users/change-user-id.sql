
-- Replace an OMP user id with another

DECLARE @err INT , @rows INT , @keep VARCHAR(32) , @remove VARCHAR(32)

SELECT @remove = UPPER( 'id-to-remove'  )
SELECT @keep   = UPPER( 'id-to-replace-with'  )

print "** To replace: %1! -> %2!" , @remove , @keep

  SELECT count(*) , 'count_ompfaultbody'  FROM omp..ompfaultbody  WHERE author        = @remove
  SELECT count(*) , 'count_ompfeedback'   FROM omp..ompfeedback   WHERE author        = @remove
  SELECT count(*) , 'count_ompshiftlog'   FROM omp..ompshiftlog   WHERE author        = @remove
  SELECT count(*) , 'count_ompobslog'     FROM omp..ompobslog     WHERE commentauthor = @remove
  SELECT count(*) , 'count_ompproj'       FROM omp..ompproj       WHERE pi            = @remove
  SELECT count(*) , 'count_ompmsbdone'    FROM omp..ompmsbdone    WHERE userid        = @remove
  SELECT count(*) , 'count_ompprojuser'   FROM omp..ompprojuser   WHERE userid        = @remove
  SELECT count(*) , 'count_ompuser'       FROM omp..ompuser       WHERE userid        = @remove

  BEGIN TRAN

  print "** Updating tables ..."
  --
  UPDATE  omp..ompfaultbody  SET  author        = @keep WHERE author        = @remove
  UPDATE  omp..ompfeedback   SET  author        = @keep WHERE author        = @remove
  UPDATE  omp..ompshiftlog   SET  author        = @keep WHERE author        = @remove
  UPDATE  omp..ompobslog     SET  commentauthor = @keep WHERE commentauthor = @remove
  UPDATE  omp..ompproj       SET  pi            = @keep WHERE pi            = @remove
  UPDATE  omp..ompmsbdone    SET  userid        = @keep WHERE userid        = @remove
  UPDATE  omp..ompprojuser   SET  userid        = @keep WHERE userid        = @remove

  UPDATE      omp..ompuser SET userid = @keep WHERE userid = @remove
  ----UPDATE      omp..ompuser SET uname = ''     WHERE userid = @remove
  ----DELETE FROM omp..ompuser                    WHERE userid = @remove

  -- This saves the rowcount to be used later of only the last SQL query.
  SELECT @err = @@error , @rows = @@rowcount

  print ""
  print "** ... Done: user id change"

  SELECT userid ,  uname , email
  FROM omp..ompuser
  WHERE userid IN ( @remove , @keep )

  IF (@err = 1205)
  BEGIN
    PRINT "Error %1, Deadlock, transaction rolled back by server", @err
  END
  ELSE IF (@err != 0)
  BEGIN
    ROLLBACK TRAN
    RAISERROR 99999 "Error %1, transaction rolled back", @err
  END
  ELSE IF (@rows != 1)
  BEGIN
    ROLLBACK TRAN  -- for completeness
    PRINT "Update affected no rows", @err
  END
  ELSE
  BEGIN
    COMMIT TRAN
    PRINT "Transaction commited"
  END

go

