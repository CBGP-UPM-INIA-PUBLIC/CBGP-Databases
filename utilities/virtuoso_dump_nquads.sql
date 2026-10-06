-- dump_nquads: writes every graph of a Virtuoso quad store, as N-Quads, into
-- numbered files (output000001.nq[.gz], ...) in a directory.
--
-- This is the procedure OpenLink Software publishes for exactly this purpose,
-- "Producing NQuad dumps of Virtuoso Quad-store hosted RDF model data"
-- (https://vos.openlinksw.com/owiki/wiki/VOS/VirtRDFDumpNQuad), reproduced
-- here unchanged except for these comments. Virtuoso does NOT ship it
-- pre-installed, so it has to be created once in each store; utilities/
-- virtuoso_nquads.sh does that for you, then runs it. Creating it again is
-- harmless (CREATE PROCEDURE replaces it).
--
-- Arguments:
--   dir                 directory to write to - relative to the store's data
--                       directory, and permitted by DirsAllowed in virtuoso.ini
--   start_from          number of the first output file
--   file_length_limit   start a new file after this many bytes
--   comp                1 = gzip each file, 0 = leave them uncompressed
--
-- The internal virtrdf: graph (Virtuoso's own schema) is skipped.
CREATE PROCEDURE dump_nquads
  ( IN  dir                VARCHAR := 'dumps'
  , IN  start_from             INT := 1
  , IN  file_length_limit  INTEGER := 100000000
  , IN  comp                   INT := 1
  )
  {
    DECLARE  inx, ses_len  INT
  ; DECLARE  file_name     VARCHAR
  ; DECLARE  env, ses      ANY
  ;

  inx := start_from;
  SET isolation = 'uncommitted';
  env := vector (0,0,0);
  ses := string_output (10000000);
  FOR (SELECT * FROM (sparql define input:storage "" SELECT ?s ?p ?o ?g { GRAPH ?g { ?s ?p ?o } . FILTER ( ?g != virtrdf: ) } ) AS sub OPTION (loop)) DO
    {
      DECLARE EXIT HANDLER FOR SQLSTATE '22023'
	{
	  GOTO next;
	};
      http_nquad (env, "s", "p", "o", "g", ses);
      ses_len := LENGTH (ses);
      IF (ses_len >= file_length_limit)
	{
	  file_name := sprintf ('%s/output%06d.nq', dir, inx);
	  string_to_file (file_name, ses, -2);
	  IF (comp)
	    {
	      gz_compress_file (file_name, file_name||'.gz');
	      file_delete (file_name);
	    }
	  inx := inx + 1;
	  env := vector (0,0,0);
	  ses := string_output (10000000);
	}
      next:;
    }
  IF (length (ses))
    {
      file_name := sprintf ('%s/output%06d.nq', dir, inx);
      string_to_file (file_name, ses, -2);
      IF (comp)
	{
	  gz_compress_file (file_name, file_name||'.gz');
	  file_delete (file_name);
	}
      inx := inx + 1;
      env := vector (0,0,0);
    }
}
;
