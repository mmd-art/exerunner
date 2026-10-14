#define UNICODE
#define _UNICODE
#include <windows.h>
#include <msi.h>
#include <msiquery.h>
#include <stdio.h>

static UINT query(MSIHANDLE db, const wchar_t *sql) {
    MSIHANDLE view=0; UINT code=MsiDatabaseOpenViewW(db,sql,&view);
    if(!code)code=MsiViewExecute(view,0);
    if(view)MsiCloseHandle(view);
    if(code)fwprintf(stderr,L"MSI SQL status %u: %ls\n",code,sql);
    return code;
}
int main(void) {
    MSIHANDLE db=0, summary=0; UINT code=MsiOpenDatabaseW(L"probe.msi",MSIDBOPEN_CREATE,&db);
    if(code)return code;
    const wchar_t *tables[]={
      L"CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(0) PRIMARY KEY `Property`)",
      L"CREATE TABLE `Directory` (`Directory` CHAR(72) NOT NULL, `Directory_Parent` CHAR(72), `DefaultDir` CHAR(255) NOT NULL PRIMARY KEY `Directory`)",
      L"CREATE TABLE `Component` (`Component` CHAR(72) NOT NULL, `ComponentId` CHAR(38), `Directory_` CHAR(72) NOT NULL, `Attributes` SHORT NOT NULL, `Condition` CHAR(255), `KeyPath` CHAR(72) PRIMARY KEY `Component`)",
      L"CREATE TABLE `Feature` (`Feature` CHAR(38) NOT NULL, `Feature_Parent` CHAR(38), `Title` CHAR(64), `Description` CHAR(255), `Display` SHORT, `Level` SHORT NOT NULL, `Directory_` CHAR(72), `Attributes` SHORT NOT NULL PRIMARY KEY `Feature`)",
      L"CREATE TABLE `FeatureComponents` (`Feature_` CHAR(38) NOT NULL, `Component_` CHAR(72) NOT NULL PRIMARY KEY `Feature_`, `Component_`)",
      L"CREATE TABLE `File` (`File` CHAR(72) NOT NULL, `Component_` CHAR(72) NOT NULL, `FileName` CHAR(255) NOT NULL, `FileSize` LONG NOT NULL, `Version` CHAR(72), `Language` CHAR(20), `Attributes` SHORT, `Sequence` SHORT NOT NULL PRIMARY KEY `File`)",
      L"CREATE TABLE `Media` (`DiskId` SHORT NOT NULL, `LastSequence` LONG NOT NULL, `DiskPrompt` CHAR(64), `Cabinet` CHAR(255), `VolumeLabel` CHAR(32), `Source` CHAR(72) PRIMARY KEY `DiskId`)",
      L"CREATE TABLE `InstallExecuteSequence` (`Action` CHAR(72) NOT NULL, `Condition` CHAR(255), `Sequence` SHORT PRIMARY KEY `Action`)"
    };
    for(unsigned i=0;i<sizeof(tables)/sizeof(tables[0]);i++)if((code=query(db,tables[i])))goto done;
    const wchar_t *rows[]={
      L"INSERT INTO `Property` (`Property`,`Value`) VALUES ('ProductCode','{77F77F01-7188-4F09-A53C-000000000001}')",
      L"INSERT INTO `Property` (`Property`,`Value`) VALUES ('ProductName','ExeRunner General MSI Probe')",
      L"INSERT INTO `Property` (`Property`,`Value`) VALUES ('ProductVersion','1.0.0')",
      L"INSERT INTO `Property` (`Property`,`Value`) VALUES ('Manufacturer','ExeRunner')",
      L"INSERT INTO `Property` (`Property`,`Value`) VALUES ('ProductLanguage','1033')",
      L"INSERT INTO `Directory` (`Directory`,`DefaultDir`) VALUES ('TARGETDIR','SourceDir')",
      L"INSERT INTO `Directory` (`Directory`,`Directory_Parent`,`DefaultDir`) VALUES ('ProgramFilesFolder','TARGETDIR','.')",
      L"INSERT INTO `Directory` (`Directory`,`Directory_Parent`,`DefaultDir`) VALUES ('INSTALLDIR','ProgramFilesFolder','ExeRunnerProbe:.')",
      L"INSERT INTO `Component` (`Component`,`ComponentId`,`Directory_`,`Attributes`,`KeyPath`) VALUES ('Main','{77F77F01-7188-4F09-A53C-000000000002}','INSTALLDIR',0,'Payload')",
      L"INSERT INTO `Feature` (`Feature`,`Title`,`Display`,`Level`,`Directory_`,`Attributes`) VALUES ('Probe','Probe',1,1,'INSTALLDIR',0)",
      L"INSERT INTO `FeatureComponents` (`Feature_`,`Component_`) VALUES ('Probe','Main')",
      L"INSERT INTO `Media` (`DiskId`,`LastSequence`) VALUES (1,1)"
    };
    for(unsigned i=0;i<sizeof(rows)/sizeof(rows[0]);i++)if((code=query(db,rows[i])))goto done;
    WIN32_FILE_ATTRIBUTE_DATA attr;
    if(!GetFileAttributesExW(L"probe.exe",GetFileExInfoStandard,&attr)){code=GetLastError();goto done;}
    wchar_t row[512];
    swprintf(row,512,L"INSERT INTO `File` (`File`,`Component_`,`FileName`,`FileSize`,`Attributes`,`Sequence`) VALUES ('Payload','Main','probe.exe',%u,8192,1)",attr.nFileSizeLow);
    if((code=query(db,row)))goto done;
    struct {const wchar_t *action;int sequence;} actions[]={
      {L"CostInitialize",800},{L"FileCost",900},{L"CostFinalize",1000},{L"InstallValidate",1400},
      {L"InstallInitialize",1500},{L"ProcessComponents",1600},{L"CreateFolders",3700},{L"InstallFiles",4000},
      {L"RegisterUser",6000},{L"RegisterProduct",6100},{L"PublishFeatures",6300},{L"PublishProduct",6400},{L"InstallFinalize",6600}
    };
    for(unsigned i=0;i<sizeof(actions)/sizeof(actions[0]);i++){
        swprintf(row,512,L"INSERT INTO `InstallExecuteSequence` (`Action`,`Sequence`) VALUES ('%ls',%d)",actions[i].action,actions[i].sequence);
        if((code=query(db,row)))goto done;
    }
    if((code=MsiGetSummaryInformationW(db,NULL,5,&summary)))goto done;
    if((code=MsiSummaryInfoSetPropertyW(summary,7,VT_LPSTR,0,NULL,L"Intel;1033")))goto done;
    if((code=MsiSummaryInfoSetPropertyW(summary,9,VT_LPSTR,0,NULL,L"{77F77F01-7188-4F09-A53C-000000000003}")))goto done;
    if((code=MsiSummaryInfoSetPropertyW(summary,14,VT_I4,200,NULL,NULL)))goto done;
    if((code=MsiSummaryInfoSetPropertyW(summary,15,VT_I4,0,NULL,NULL)))goto done;
    if((code=MsiSummaryInfoPersist(summary)))goto done;
    code=MsiDatabaseCommit(db);
done:
    if(summary)MsiCloseHandle(summary);MsiCloseHandle(db);
    printf("MSI_FIXTURE %u\n",code);return code;
}
