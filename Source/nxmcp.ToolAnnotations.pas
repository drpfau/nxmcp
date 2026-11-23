unit nxmcp.ToolAnnotations;

/// <summary>
///  MCP tool annotations (tools/list "annotations") for the nxmcp tools.
///
///  The spec defaults for a tool without annotations are readOnlyHint=false,
///  destructiveHint=true, idempotentHint=false, openWorldHint=true. Clients use the
///  hints to auto-approve or parallelise calls, so every tool states all of them
///  explicitly through AnnotateTool, called from its constructor. The library's
///  MarkReadOnly only covers the read-only case.
///
///  The hints are a promise to the client, not an enforcement: a tool marked
///  tkReadOnly must not change anything - no data, no schema, no session or server
///  state. When in doubt, use a weaker kind.
/// </summary>

interface

uses
  System.JSON;

type
  TnxToolKind = (
    /// <summary>Changes nothing (readOnlyHint=true).</summary>
    tkReadOnly,
    /// <summary>Writes, loses nothing, but repeating it has another effect
    /// (or fails): inserts, creates, renames.</summary>
    tkAdditive,
    /// <summary>Writes, loses nothing, and repeating it with the same
    /// arguments has no further effect: set_*, switches, reindex.</summary>
    tkIdempotent,
    /// <summary>May overwrite or remove data, structure or access, or block
    /// later writes (destructiveHint=true).</summary>
    tkDestructive
  );

/// <summary>
///  Sets readOnlyHint, destructiveHint, idempotentHint and openWorldHint on
///  Annotations (created when nil; the tool base frees it). openWorldHint is always
///  false: every tool works only on the NexusDB server it is connected to.
/// </summary>
procedure AnnotateTool(var Annotations: TJSONObject; Kind: TnxToolKind);

implementation

uses
  MCPServer.Types;

const
  // MCPServer.Types only names the read-only and open-world hints.
  cDestructiveHint = 'destructiveHint';
  cIdempotentHint = 'idempotentHint';

procedure SetHint(Annotations: TJSONObject; const Name: string; Value: Boolean);
begin
  Annotations.RemovePair(Name).Free;
  Annotations.AddPair(Name, TJSONBool.Create(Value));
end;

procedure AnnotateTool(var Annotations: TJSONObject; Kind: TnxToolKind);
begin
  if not Assigned(Annotations) then
    Annotations := TJSONObject.Create;
  SetHint(Annotations, MCP_ANNOTATION_READ_ONLY_HINT, Kind = tkReadOnly);
  SetHint(Annotations, MCP_ANNOTATION_OPEN_WORLD_HINT, False);
  // The spec gives destructiveHint/idempotentHint meaning only when readOnlyHint is
  // false, so a read-only tool carries just the two hints above.
  if Kind <> tkReadOnly then
  begin
    SetHint(Annotations, cDestructiveHint, Kind = tkDestructive);
    SetHint(Annotations, cIdempotentHint, Kind = tkIdempotent);
  end;
end;

end.
