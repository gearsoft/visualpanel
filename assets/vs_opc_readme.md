# vs_opc integration — HMI asset README

This short snippet explains how the Flutter HMI (frontend) can interact with the `vs_opc` Python gateway. It includes example JSON payloads adjusted to the schema used by the HMI's `plc_config.json` (found in this folder).

Note: the gateway expects tags to be created/managed via the REST API at runtime. The HMI can POST tag definitions on first run or provide a separate management UI to create tags.

---

## Example PLC frontend schema (from `plc_config.json`)

Frontend uses a structure like:

```json
{
  "plcs": [
    {
      "plc_id": "compactlogix",
      "host": "192.168.32.201",
      "type": "compactlogix",
      "tags": [
        {
          "tag_id": "ABS1_Auto",
          "name": "ABS1_Auto",
          "address": "ABS01.HMI.AUTO.ST",
          "data_type": "Boolean"
        }
      ]
    }
  ]
}
```

The gateway REST API accepts tag definitions with the same fields. The examples below use the gateway's REST endpoints.

## Create a tag (example)

POST /api/v1/tags

Body (JSON):

```json
{
  "plc_id": "compactlogix",
  "tag_id": "ABS1_Auto",
  "name": "ABS1_Auto",
  "address": "ABS01.HMI.AUTO.ST",
  "data_type": "Boolean",
  "value": true
}
```

Notes:
- `plc_id` must match the PLC logical id you plan to use (e.g., `compactlogix` or `slc500`).
- `tag_id` is the unique identifier used by the TagStore and by the HMI when referencing the tag.
- `address` is the PLC address the driver will read/write (for mock mode it is only informational).
- `data_type` can be `Boolean`, `Double`, `Int32`, `Decimal`, etc., as used by your frontend.

## Create a Decimal tag with scale/decimals (example)

For fixed-point values (SLC tags or scaled integers) include `scale_mul` and `decimals` if needed:

POST /api/v1/tags

```json
{
  "plc_id": "slc500",
  "tag_id": "M1_Batch_Weight",
  "name": "M1_Batch_Weight",
  "address": "N89:14",
  "data_type": "Decimal",
  "scale_mul": 0.1,
  "decimals": 2,
  "value": "12.30"
}
```

Notes about `value` and Decimal handling:
- If you pass a `value` string that looks like a decimal (e.g. "12.30"), the gateway will store it using Python's `decimal.Decimal` (if the tag's datatype is Decimal or the frontend provides a Decimal string).
- When the gateway returns values to the HMI, it follows this rule:
  - If the stored/raw value is `int` or `float`, the API returns a JSON number (no quotes).
  - If the stored/raw value is `decimal.Decimal`, the API returns a JSON string that preserves the exact textual representation (e.g., "1.2300"). This preserves trailing zeros and formatting that an HMI may depend on.

This means the frontend should be prepared to accept either a JSON number or a string for numeric fields, and parse Decimal strings into its internal fixed-point/Decimal representation when exact formatting is required.

## Update a tag value (example)

PATCH /api/v1/tags/M1_Batch_Weight

Body (JSON):

```json
{
  "value": "1.2300"
}
```

Response (example when returning Decimal preserved):

```json
{
  "tag_id": "M1_Batch_Weight",
  "value": "1.2300"
}
```

Example when a numeric value (int/float) is returned:

```json
{
  "tag_id": "ABS1_CFA_Actual",
  "value": 150.0
}
```

## Fetch current HMI data

GET /api/v1/hmi/data

Response (snapshot):

```json
{
  "ABS1_Auto": true,
  "ABS1_CFA_Actual": 150.0,
  "M1_Batch_Weight": "12.30"
}
```

## Tips for the Flutter HMI

- When displaying Decimal values, prefer parsing string Decimal values into a Decimal/fixed-point model so you can preserve formatting and trailing zeros.
- For simple numeric-only displays you can accept either numbers or parse numeric strings.
- On initial HMI startup, POST your `plc_config.json` tags to the gateway (or implement a small sync endpoint in the HMI) to ensure the TagStore is populated before the first poll.

If you'd like, I can also add an example Dart snippet that converts the API responses into typed models in your Flutter app — say the word and I will add it to this file.
