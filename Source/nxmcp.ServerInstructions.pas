unit nxmcp.ServerInstructions;

/// <summary>
///  The "instructions" text nxmcp sends in the initialize result. Clients add it to
///  the model's context, so it carries what an AI caller otherwise gets wrong with
///  NexusDB. Keep it short and keep it true: update it whenever tool behaviour or a
///  rule in CLAUDE.md that it repeats changes. [Server] Instructions in nxmcp.ini
///  replaces it per installation.
/// </summary>

interface

const
  cServerInstructions =
    'nxmcp gives access to one NexusDB database. NexusDB SQL is close to SQL:2003, not' + #10 +
    'T-SQL or MySQL. Quote identifiers with double quotes, strings with single quotes.' + #10 +
    #10 +
    'Typed values: GUID, DATE, TIME and DATETIME columns do not accept plain strings.' + #10 +
    'Prefer :name parameters with "type" (guid/date/time/datetime) via the params argument' + #10 +
    'of execute_query / execute_sql. In raw SQL use typed literals:' + #10 +
    '  GUID ''{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}''  (braces required)' + #10 +
    '  DATE ''YYYY-MM-DD''   TIME ''HH:MM:SS''   TIMESTAMP ''YYYY-MM-DD HH:MM:SS''  (space, not T)' + #10 +
    'Query results return DATETIME as ISO 8601 with T and a UTC offset; strip both before' + #10 +
    'writing a value back. insert_record / update_records convert values themselves.' + #10 +
    #10 +
    'Tools: execute_query runs one SELECT only. Writes go through execute_sql or the record' + #10 +
    'tools. batch_execute runs statements one by one in one transaction, so #temp tables do' + #10 +
    'not survive to the next statement. Use get_table_schema before writing to a table you' + #10 +
    'do not know. DDL cannot run inside a transaction.' + #10 +
    #10 +
    'run_script runs a whole script as ONE batch (SELECT ... INTO #temp chains, variables,' + #10 +
    'cursors) and returns the last result set. The default transaction="rollback" undoes' + #10 +
    'everything; transaction="commit" keeps the changes. transaction="none" (needed for DDL)' + #10 +
    'starts no transaction: what the script does persists, also when a later statement' + #10 +
    'fails - it is never a dry run. Its result format differs from' + #10 +
    'execute_query: rows are arrays in column order, column names are exactly as NexusDB' + #10 +
    'returns them (not camelCased), DATETIME has no offset. A failing script is a tool error' + #10 +
    'whose text is JSON with the exact NexusDB message in "error".' + #10 +
    #10 +
    'Dialect specifics: DROP INDEX "table"."index"; ALTER TABLE "old" RENAME TO "new" RESTRICT.' + #10 +
    'Catalog: #TABLES, #FIELDS, #INDEXES (columns like TABLE_NAME). There is no EXPLAIN:' + #10 +
    'use explain_query, or prefix a statement with #L+ (plan) / #V+ (verbose) and read' + #10 +
    'get_query_log.' + #10 +
    #10 +
    'All calls share one database session and run one at a time; long maintenance' + #10 +
    'operations (pack, reindex, restructure) block other calls until they finish.';

implementation

end.
