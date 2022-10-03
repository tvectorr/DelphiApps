program DeleteOldFiles;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils;

var
  sOri: string;
  sPath, sMask: string;
  nCop, nDel: integer;


// Preencher os parametros passados
// /copies:8 /path:<caminho> /mask:<mascara para excuir>
function FillCommandParams: boolean;
begin
  Result := FindCmdLineSwitch('copies', sOri);
  if Result then
    nCop := StrToIntDef(sOri, 0);

  Result := Result and FindCmdLineSwitch('path', sPath);

  if Result then
    sPath := IncludeTrailingPathDelimiter(sPath);

  Result := Result and FindCmdLineSwitch('mask', sMask);

  Result := Result and (nCop > 0) and (sPath > '') and (sMask > '');
end;



{ Buscar lista de arquivos ordenados por data }
function GetFileListSortedByDate(APath, AMask: string): TStringList;
var
  fFile: TSearchRec;
  sS, sFileName: string;

begin
  //
  Result := TStringList.Create;

  try
    sS := TPath.GetDirectoryName(APath) + TPath.DirectorySeparatorChar;

    // Arquivos no diretorio
    if FindFirst( sS + AMask, faAnyFile, fFile ) = 0 then
    repeat
      if (fFile.Attr <> faDirectory) then
      begin
        sFileName := sS + fFile.Name;

        Result.Add( FormatDateTime('yyyymmddhhnnss', fFile.TimeStamp ) +'='+
                    sFilename  );
      end;

        //AList.Add(sS + fFile.Name);
    until FindNext(fFile) <> 0;

  finally
    FindClose(fFile);

    // Sort por data
    Result.Sort;
  end;
end;


function DeleteFileList: boolean;
var
  sFileList: TStringList;
begin
  sFileList := nil;
  try
    Result := True;

    nDel := 0;

    sFileList := GetFileListSortedByDate(sPath, sMask);

    while Result and (sFileList.Count > nCop) do
    begin
      sOri := sFileList.ValueFromIndex[0];
      Result := System.SysUtils.DeleteFile( sOri );

      if Result then
      begin
        Inc(nDel);
        sFileList.Delete(0);
      end;

    end;
  finally
    sFileList.Free;
  end;

end;


begin
  { Apaga os arquivos mais antigos, mantendo <copies> cópias mais recentes }

  writeln('');
  writeln('DeleteOldFiles v3.1');
  writeln('(c) 2021 - Via Regra ');
  writeln('');

  if (not FillCommandParams) then
  begin
    writeln( ' Syntax: ' );
    writeln( ' DeleteOldFiles /copies:<Copies to keep> /path:<destination folder>' );
    writeln( '                /mask:<file mask to delete>' );
    writeln('');
    writeln( ' Sample: ' );
    writeln( ' DeleteOldFiles /copies:8 /path:C:\Backup /mask:*.rar' );
    writeln('');

    Exit;
  end;

  if (not DeleteFileList) then
    writeln('Falha ao excluir '''+ sOri +'''');

  writeln( nDel.ToString + ' arquivos excluídos');

end.
