# Dependencies

The external code nxmcp is built against. Versions are not pinned anywhere in the
project files, so they are recorded here.

| Library | Version used | Stock? |
|---|---|---|
| [Delphi-MCP-Server](https://github.com/GDKsoftware/Delphi-MCP-Server) | `f950352` (2026-11-17) | yes — needs TaurusTLS installed (`USE_TAURUS_TLS` is on by default) |
| [dataset-serialize](https://github.com/viniciussanchez/dataset-serialize) | `1330615` (2025-11-17) | no — one patch, see below |
| NexusDB | 4.75 (commercial) | yes |

Delphi 13 / RAD Studio 37, Win64.

## Delphi-MCP-Server: library path

nxmcp resolves the library through the RAD Studio global library path (Win64), not a
project search path. Since `f950352` it needs `src` itself and `src\Prompts` in addition
to the subfolders, or the build stops with F1026 `MCPServer.inc` not found:

```text
<lib>\src            MCPServer.inc (the USE_TAURUS_TLS switch)
<lib>\src\Core
<lib>\src\Http
<lib>\src\Managers
<lib>\src\Prompts    used by MCPServer.Registration
<lib>\src\Protocol
<lib>\src\Resources
<lib>\src\Server
<lib>\src\Tools
```

MSBuild (and therefore command-line builds) reads the same list from
`%APPDATA%\Embarcadero\BDS\37.0\EnvOptions.proj`, which the IDE rewrites when the
library options are saved.

From `f950352` on, `initialize` builds its capabilities only from managers implementing
`IMCPCapabilityProvider`, so nxmcp needs the forwarding in `nxmcp.CapabilityFilter` /
`nxmcp.SerializedManager` (PR #7); without it clients list no tools.

The library also registers its own `server://status` resource (uptime, memory, request
count). Upstream's `[Server] ExposeDiagnosticsResources` switch only applies to
`TMCPServerHost`, which nxmcp does not use; hide it with `[Resources] server://status=0`.

## dataset-serialize: ftLongWord patch required

Upstream serialises `ftLongWord` through `AsInteger`, which raises
`RangeError(Value, 0, High(Integer))` for any value above 2 147 483 647 — so a table
with a Cardinal-range column breaks every tool that returns rows. Apply this to
`src/DataSet.Serialize.Export.pas`, in the field-type case:

```pascal
{$IF NOT DEFINED(FPC)}
TFieldType.ftLongWord:
  Result.AddPair(LKey, TJSONNumber.Create(LField.AsLargeInt));
{$ENDIF}
```

and remove `TFieldType.ftLongWord` from the `ftInteger` branch above it. The fix is not
in upstream at any commit, so it must be re-applied after every update.
