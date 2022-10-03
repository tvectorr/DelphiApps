program DeleteFoldersFiles;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, Windows;

const
  clCOPDEF = 8;
  clCOPDEFKEY = 'DefaultCopies';
  clDELCMD = 'DeleteOldFiles.exe';

var
  sOri: string;
  sPath, sMask: string;
  nCop, nCopDef{, nDel}: integer;
  sIniFile, sCmdFile: string;
  sFolderList: TStringList;


{ Retirado da SatBak.FuBak.pas  }
procedure UpdateStringList(ALines: TStringList; const ALine: AnsiString);
var
  sLin: AnsiString;
  iPos: integer;
begin
  sLin := ALine;

  if (ALines.Text <> sLineBreak) then
    sLin := StringReplace(sLin, ALines.Text, '', [rfReplaceAll]);

  iPos := Pos(sLineBreak, sLin);

  while (iPos > 0) do
  begin
    ALines.Add(Copy(sLin, 1, iPos-1));
    sLin := Copy(sLin, iPos+2, Length(sLin));
    iPos := Pos(sLineBreak, sLin);
  end;
end;


{ Retirado da SatBak.FuBak.pas - Capturar a saída do DOS }
function GetDosOutput(const ACommandLine, ACommandParams: string; var ALines: TStringList ): string;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  StdOutPipeRead, StdOutPipeWrite: THandle;
  WasOK: Boolean;
  // XE
  //Buffer: array[0..255] of Char;
  Buffer: array[0..255] of AnsiChar;
  BytesRead: Cardinal;
  WorkDir{, Line}: String;
  // XE
  Line: AnsiString;
begin
  Line := '';

  with SA do
  begin
    nLength := SizeOf(SA);
    bInheritHandle := True;
    lpSecurityDescriptor := nil;
  end;

  // create pipe for standard output redirection
  CreatePipe(StdOutPipeRead, // read handle
             StdOutPipeWrite, // write handle
             @SA, // security attributes
             0 // number of bytes reserved for pipe - 0 default
             );
  try
    try
      // Make child process use StdOutPipeWrite as standard out,
      // and make sure it does not show on screen.
      with SI do
      begin
        FillChar(SI, SizeOf(SI), 0);
        cb := SizeOf(SI);
        dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
        wShowWindow := SW_HIDE;
        hStdInput := GetStdHandle(STD_INPUT_HANDLE); // don't redirect std input
        hStdOutput := StdOutPipeWrite;
        hStdError := StdOutPipeWrite;
      end;

      // launch the command line compiler
      WorkDir := ExtractFilePath(ACommandLine);

      //WasOK := CreateProcess(PChar(ACommandLine), PChar(ACommandParams),
      WasOK := CreateProcess(nil, PChar(ACommandLine +' '+ ACommandParams),
                             nil, nil, True, 0, nil,
                             PChar(WorkDir), SI, PI);

      // Now that the handle has been inherited, close write to be safe.
      // We don't want to read or write to it accidentally.
      CloseHandle(StdOutPipeWrite);

      // if process could be created then handle its output
      if not WasOK then
        raise Exception.Create('Não foi possivel executar o comando!')
      else
      try
        // get all output until dos app finishes
        Line := '';

        repeat
          // read block of characters (might contain carriage returns and line feeds)
          WasOK := ReadFile(StdOutPipeRead, Buffer, 255, BytesRead, nil);

          // has anything been read?
          if BytesRead > 0 then
          begin
            // finish buffer to PChar
            Buffer[BytesRead] := #0;
            // combine the buffer with the rest of the last run
            Line := Line + Buffer;

            // Capturar saida para o TString
            UpdateStringList(ALines, Line);
            //ALines.Text := Line;
            //Application.ProcessMessages;
          end;
        until not WasOK or (BytesRead = 0);

        // wait for console app to finish (should be already at this point)
        WaitForSingleObject(PI.hProcess, 60000); // INFINITE);
      finally
        //ExitThread(PI.hThread);
        //ExitProcess(PI.hProcess);

        // Close all remaining handles
        CloseHandle(PI.hThread);
        CloseHandle(PI.hProcess);
      end;

    except
      on E: Exception do
        UpdateStringList(ALines, E.Message);
    end;
  finally
    Result := Line;
    CloseHandle(StdOutPipeRead);

    // teste
    FillChar(SA, SizeOf(SA), 0);
    FillChar(SI, SizeOf(SI), 0);
    FillChar(PI, SizeOf(PI), 0);
  end;

end;


// Preencher os parametros passados
// /copies:8 /path:<caminho> /mask:<mascara para excuir>
function FillCommandParams: boolean;
begin
  Result := FindCmdLineSwitch('path', sPath);

  if Result then
    sPath := IncludeTrailingPathDelimiter(sPath);

  Result := Result and FindCmdLineSwitch('mask', sMask);

  Result := Result and (sPath > '') and (sMask > '');
end;



{ Buscar lista de arquivos ordenados por data }
procedure GetFolderListSorted(APath: string; AFolderList: TStringList);
var
  fFile: TSearchRec;
  sS, sFileName: string;

begin
  //
  //Result := TStringList.Create;

  try
    sS :=   TPath.GetDirectoryName( APath + TPath.DirectorySeparatorChar );

    // Arquivos no diretorio
    if System.SysUtils.FindFirst( TPath.Combine( sS,  '*'), faDirectory, fFile ) = 0 then
    repeat
      if (fFile.Attr = faDirectory) and (fFile.Name <> '.') and (fFile.Name <> '..') then
      begin
        sFileName := TPath.Combine( sS, fFile.Name );

        AFolderList.Add( sFilename  );

        // Chamar recursivamente
        GetFolderListSorted(sFileName, AFolderList);
      end;


        //AList.Add(sS + fFile.Name);
    until System.SysUtils.FindNext(fFile) <> 0;

  finally
    System.SysUtils.FindClose(fFile);

    // Sort por data
    //Result.Sort;
  end;
end;


function CallDeleteFileList: boolean;
var
  sPar: string;
  sFileList: TStringList;
  sResult, sLog: TStringList;
  I, J: Integer;


        function GetCopies: integer;
        var
          n: integer;
        begin
          Result := nCopDef;

          for n := 0 to sFolderList.Count-1 do
          begin
            if (Pos( LowerCase( TPath.DirectorySeparatorChar + sFolderList.Names[n] ), LowerCase( sOri ) ) > 0) then
              Result := StrToIntDef(sFolderList.ValueFromIndex[n], nCopDef);
          end;
        end;


        function GetLogFilename: string;
        var
          sCmp: string;
          c: Char;
        begin
          sCmp := sMask;

          for c in TPath.GetInvalidFileNameChars do
            sCmp := StringReplace(sCmp, c, '', [rfReplaceAll, rfIgnoreCase]);

          sCmp := StringReplace(sCmp, '.', '', [rfReplaceAll, rfIgnoreCase]);

          Result := TPath.ChangeExtension(ParamStr(0), sCmp + '.log');
        end;


begin
  Result := True;

  sFileList := TStringList.Create;;
  sResult := TStringList.Create;
  sLog := TStringList.Create;


  try
    nCopDef := clCOPDEF;

    if (sFolderList.IndexOfName(clCOPDEFKEY) >= 0) then
      nCopDef := StrToIntDef(sFolderList.Values[clCOPDEFKEY], clCOPDEF);


    //nDel := 0;

    GetFolderListSorted(sPath, sFileList);

    // Ordenar
    sFileList.Sort;

      // retorno no console
    writeln(' Iniciando...');

    for I := 0 to sFileList.Count-1 do
    begin
      sOri := sFileList[i];

      //nCop := nCopDef;

      //if (sFolderList.IndexOfName(sOri) > 0) then
      //  nCop := StrToIntDef(sFileList.Values[sOri], nCopDef);

      nCop := GetCopies;

      // Chamada à DeleteOldFiles, montar lista de parametros
      // DeleteOldFiles.exe  /copies:<nCop> /mask:<sMask> /path:<sOri>
      sPar := '/copies:' + nCop.ToString +' /mask:'+ sMask +' /path:'+ sOri;

      // retorno no console
      sLog.Add('>>> '+ DateTimeToStr(Now) +': Starting "'+ TPath.GetFileNameWithoutExtension( sCmdFile ) +' '+ sPar +'"');
      sLog.Add('');
      writeln(sLog[ sLog.Count-1 ]);

      // Chamada ao comando
      GetDosOutput(sCmdFile, sPar, sResult);

      // Adicionar ao log
      sLog.AddStrings(sResult);

      // retorno no console
      for J := 0 to sResult.Count-1 do
        writeln('    '+ sResult[j]);

      sLog.Add('');
      sLog.Add('>>> '+ DateTimeToStr(Now)+': Done "'+ TPath.GetFileNameWithoutExtension( sCmdFile ) +' '+ sPar +'"' );
      writeln(sLog[ sLog.Count-1 ]);

      sLog.Add('----------' );
      writeln( '----------' );

      // Limapar result
      sResult.Clear;

    end;

     // retorno no console
    writeln(' Concluído !');

    sLog.SaveToFile(GetLogFilename); //( TPath.ChangeExtension(ParamStr(0), '.log') );

  finally
    sFileList.Free;
    sResult.Free;
    sLog.Free;
  end;

end;


begin
  { Chamadas sucessivas a DeleteOldFiles, passando as pastas lidas no diretorio }

  try
    sFolderList := TStringList.Create;
    sIniFile := TPath.ChangeExtension(ParamStr(0), '.ini');
    sCmdFile := TPath.ChangeExtension( TPath.Combine( TPath.GetDirectoryName(sIniFile), clDELCMD ), '.exe');


    writeln('');
    writeln('DeleteFoldersFiles v3.3');
    writeln('(c) 2022 - Via Regra ');
    writeln('');

    if (not FillCommandParams) or (not TFile.Exists(sCmdFile)) then
    begin
      writeln( ' Syntax: ' );
      writeln( ' DeleteFoldersFiles /path:<root destination folder>' );
      writeln( '                    /mask:<file mask to delete>' );
      writeln('');
      writeln( ' Sample: ' );
      writeln( ' DeleteFoldersFiles  /path:D:\Mega\backupcmd /mask:*.rar' );
      writeln('');
      writeln( ' Requires:' );
      writeln( '  - DeleteOldFiles.exe on same folder' );
      writeln( '  - DeleteFoldersFiles.ini for copies customization on same folder (optional)' );

      if (not TFile.Exists(sCmdFile)) then
      begin
        writeln('');
        writeln( ' WARNING: '+ sCmdFile + ' not found!' );
      end;

      Exit;
    end;

    sIniFile := TPath.ChangeExtension(ParamStr(0), '.ini');

    if TFile.Exists( sIniFile ) then
      sFolderList.LoadFromFile(sIniFile);

    CallDeleteFileList;

    //if (not CallDeleteFileList) then
    //  writeln('Falha ao excluir '''+ sOri +'''');

    //writeln( nDel.ToString + ' arquivos excluídos');
  finally
    sFolderList.Free;
  end;

end.
