# Cloud Foundry Application Metadata Extractor (v3 API)

`pcfusage-v3.sh` collects Cloud Foundry org, space, app, and process metadata using the **v3 API**.  
It produces a CSV report for auditing, reporting, and migration analysis (e.g., CF → OpenShift).

## Features
- Works on foundations with v2 API disabled  
- Exports org, space, app, memory, disk, buildpack, and route info  
- Handles empty results safely  
- Optional `--debug` mode for verbose output  

## Requirements
- Logged into Cloud Foundry (`cf login`)  
- `cf` CLI and `jq` installed  

## Usage
```bash
chmod +x pcfusage-v3.sh
./pcfusage-v3.sh <org_name> [--debug]
```

Example:
```bash
./pcfusage-v3.sh abc-company
```

## Output
Generates a CSV file such as:
```
pcfusage_abc-company_20251113.csv
```
Sample content:
```
Org,Space,App,Process Type,Instances,Memory(MB),Disk(MB),State,Buildpacks,Routes
abc-company,sales,nginx,web,1,512,512,STARTED,staticfile_buildpack,nginx.bosh-lite.com
```

## Common Uses
- Migration inventory (CF → OpenShift)
- Resource and buildpack audit
- Reporting app configurations


