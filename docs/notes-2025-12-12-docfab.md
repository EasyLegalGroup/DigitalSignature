# Notes — 2025-12-12 (penneo-sandbox)

## DocFab: permissions & selection refactor

- Switched DocFab access control to **form-permission-only** (Record Model permissions are no longer enforced).
- Record Model is now inferred from `DocFab_Form__mdt.Record_Model__c`.
- Updated `dFJ_JournalFormComponent` to remove `recordModelIds` page-layout config.
- Updated `DFJ_JournalForm.getJournalData_Apex(...)` to no longer require a Record Model ID from the component.

Touched files:

- `force-app/main/default/classes/DF_DocFabricator_Utility.cls`
- `force-app/main/default/classes/DFJ_JournalForm.cls`
- `force-app/main/default/lwc/dFJ_JournalFormComponent/*`

## DocFab: removed legacy Custom Metadata Types in penneo-sandbox

Deleted (org-side) via destructive deploy:

- `DocFab_Model_Override__mdt`
- `DocFab_Model_Selection__mdt`
- `Record_form_configuration__mdt`
- `Journal_Address_Configration__mdt`
- `DFJ_JournalDocfabFieldConfigurator__mdt`
- `DFJ_ObjectRecordModelId__mdt`

Destructive deploy package kept in repo:

- `mdapi/delete-unused-cmdt/`

Deploy IDs (penneo-sandbox):

- `0AfG500000OjO1xKAF` (first set)
- `0AfG500000OjO5BKAV` (DFJ_ObjectRecordModelId\_\_mdt)
