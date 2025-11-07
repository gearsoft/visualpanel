# VS_OPC / VisualPanel sample assets

This small README lives alongside sample HMI assets used by the VisualPanel Flutter app.

Purpose
- Provide a small example `plc_config.json` you can open with the HMI's file picker.
- Show the JSON shape that the HMI expects (top-level `plcs`) so the app can transform it into a gateway-importable payload.

How the HMI uses `plc_config.json`
- The sample file contains a top-level `plcs` array. Each PLC object contains an array of `tags`.
- When you open this file in the VisualPanel app, the HMI will transform each tag by injecting `plc_id` and converting the file shape to the gateway import shape:

  { "tags": [ { /* tag objects with plc_id added */ } ] }

- The HMI then PUTs the transformed payload to the gateway `PUT /api/v1/tags/import?replace_all=true` endpoint.

Gateway endpoints (useful reference)
- PUT /api/v1/tags/import?replace_all=true  — import tags in the gateway; body: { "tags": [ ... ] }
- GET  /api/v1/hmi/config                      — returns the gateway's tag metadata as { "tags": [ ... ] }
- GET  /api/v1/hmi/data                        — returns current tag values (snapshot)
- GET  /api/v1/hmi/ready                       — readiness probe (200 when ready)

Notes
- The server intentionally does not read any PLC/tag files at startup — tag and PLC information must be sent from the frontend (HMI) through the import API.
- The sample `plc_config.json` in this directory is only a convenience for local testing and examples; production systems should produce an import payload from their tooling or UI.

Example transformed import payload (what the gateway expects)

```
{
  "tags": [
    {"plc_id":"compact_1","name":"ABS1_Auto","address":"Abs1.Auto","data_type":"BOOL"},
    {"plc_id":"compact_1","name":"ABS1_CFA_Actual","address":"Abs1.CFA.Actual","data_type":"REAL","scale":1},
    {"plc_id":"slc_1","name":"SLC_Status","address":"N7:0","data_type":"INT"}
  ]
}
```

If you need to re-generate or extend the sample, keep the top-level `plcs` array shape so the HMI's file-picker code can transform it without changes.

-- The VisualPanel team
