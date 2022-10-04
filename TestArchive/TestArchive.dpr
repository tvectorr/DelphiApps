program TestArchive;

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Windows,
  IdSMTP,
  IdSSLOpenSSL,
  IdMessage,
  IdAttachmentFile,
  IdExplicitTLSClientServerBase;


var
  sPath, Smask: string;
  sCmd, sCmdPar: string;
  sFileList: TStringList;
  sLog: TStringList;


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
            //UpdateStringList(ALines, Line);
            //ALines.Text := Line;
            //Application.ProcessMessages;
          end;
        until not WasOK or (BytesRead = 0);

        // wait for console app to finish (should be already at this point)
        WaitForSingleObject(PI.hProcess, 60000); // INFINITE);
      finally
        //ExitThread(PI.hThread);
        //ExitProcess(PI.hProcess);

        // Capturar saida para o TString
        UpdateStringList(ALines, Line);

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



{ Preencher os parametros passados }
{ /path:<caminho> /mask:<mascara para excuir> /cmd:<chamar o rar> /cmdpar:<camiho para os arquivos> }
function FillCommandParams: boolean;
begin
  Result := FindCmdLineSwitch('path', sPath);

  if Result then
    sPath := IncludeTrailingPathDelimiter(sPath);

  Result := Result and FindCmdLineSwitch('mask', sMask);

  Result := Result and FindCmdLineSwitch('cmd', sCmd);

  Result := Result and FindCmdLineSwitch('cmdpar', sCmdPar);

  Result := Result and (sPath > '') and (sMask > '') and (sCmd > '') and (sCmdPar > '');
end;



{ Buscar lista de arquivos }
procedure GetFileList(APath, AMask: string; sFileList: TStringList);
var
  fFile: TSearchRec;
  sS, sFileName: string;
  I: integer;
  sRep, sPar: string;

begin

  // Pegar todos arquivos
  try
    sS :=   TPath.GetDirectoryName( APath + TPath.DirectorySeparatorChar );

    // Arquivos no diretorio
    if System.SysUtils.FindFirst( TPath.Combine( sS,  '*'), faDirectory, fFile ) = 0 then
    repeat
      if (fFile.Attr = faDirectory) and (fFile.Name <> '.') and (fFile.Name <> '..') then
      begin
        sFileName := TPath.Combine( sS, fFile.Name );

        //sFileList.Add( sFilename );

        // Chamar recursivamente
        GetFileList(sFileName, AMask, sFileList);
      end;

    until System.SysUtils.FindNext(fFile) <> 0;

  finally
    System.SysUtils.FindClose(fFile);
  end;


  try
    sS := TPath.GetDirectoryName( TPath.Combine( APath, AMask  ) ) ;

    // Arquivos no diretorio
    if FindFirst( TPath.Combine(sS, AMask), faAnyFile, fFile ) = 0 then

    repeat
      if (fFile.Attr <> faDirectory) then
      begin
        sFileName := TPath.Combine(sS, fFile.Name);

        sFileList.Add( sFilename );

        //GetFileList(sPath, sMask, sFileList);
      end;

    until System.SysUtils.FindNext(fFile) <> 0;

  finally
    System.SysUtils.FindClose(fFile);
  end;
end;




function SendEmail: boolean;
var
  LSMTP: TIdSMTP;
  LMessage: TIdMessage;
  LSocketSSL: TIdSSLIOHandlerSocketOpenSSL;
  LArquivoAnexo: string;
  Destinatario: string;

const
  //_EMAIL = 'hjacobwss@gmail.com';
  _EMAIL = 'hjacobwss@zohomail.com';
  _SENHA = 'phonesinchugo4';
  _PORTA = 465;
  //_SMTP = 'smtp.gmail.com';
  _SMTP = 'smtp.zoho.com';

begin
  LSMTP := TIdSMTP.Create( nil );
  LMessage := TIdMessage.Create( nil );
  LSocketSSL := TIdSSLIOHandlerSocketOpenSSL.Create( nil );

  Destinatario := 'suporte@viaregra.com';
  //Destinatario := 'hjacobwss@gmail.com';


  // Segurança
  with LSocketSSL do
  begin
    with SSLOptions do
    begin
      Mode := sslmClient;
      Method := sslvTLSv1_2;
    end;

    Host := _SMTP; { smtp.gmail.com / smtp.zohomail.com }
    Port := _PORTA; // 465
  end;

  // SMTP
  with LSMTP do
  begin
    IOHandler := LSocketSSL;
    HOST := _SMTP;
    PORT := _PORTA;
    AuthType := satDefault;
    Username := _EMAIL; //joao@gmail.com
    //Username := 'hugov.pessoal@gmail.com';

    Password := _SENHA;
    //Password := '1234';

    UseTLS := utUseExplicitTLS;
  end;

  // Mensagem
  with LMessage do
  begin
    From.Address := _EMAIL;
    //From.Address := 'hugov.pessoal@gmail.com';

    From.Name := _EMAIL;

    Recipients.Add;
    Recipients.Items[0].Address := Destinatario;
    Subject := ('Relatório de arquivos com erros:' +' '+ DateToStr(Now));
    Body.Add(sLog.Text);

  end;

  { Arquivos em Anexo

  // Arquivos em anexo
  LArquivoAnexo := 'C:\1coding\Delphi\TestArchive\TestArchive.rar.log';
  if LArquivoAnexo <> EmptyStr then
    //TIdAttachmentFile.Create( LMessage.MessageParts, LArquivoAnexo + 'TestArchive.rar.log' );
    TIdAttachmentFile.Create( LMessage.MessageParts, LArquivoAnexo);
  {}

  try
    LSMTP.Connect;
    LSMTP.Send( LMessage);
  finally
  end;
end;



function CallTestIntegrity: boolean;
var
  I: integer;
  sOri, sPar: string;
  sResult: TStringList;
  m, n: integer;


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
  Result := true;

  sFileList := TStringList.Create;
  sResult := TStringList.Create;
  sLog := TStringList.Create;


  try

    GetFileList(sPath, sMask, sFileList);


    for I := 0 to sFileList.Count-1 do
    begin
      sOri := sFileList[i];

      Writeln('');


      sPar := StringReplace(sCmdPar, '%s', sOri, [rfReplaceAll]);

      // Debug - exibir linha de comando
      Writeln(sCmd +' '+ sPar);

      // Chamada ao comando
      GetDosOutput(sCmd, sPar, sResult);

      // Exibir resultado da chamda
      if (sResult.Text.Contains('error')) then
      begin
        writeln(sResult.Text);

        // retorno no console
        sLog.Add('>>> '+ DateTimeToStr(Now) +': Starting "'+ TPath.GetFileNameWithoutExtension( sCmd ) +' '+ sPar +'"');

        sLog.Add('');
        writeln(sLog[ sLog.Count-1 ]);

        // Adicionar ao log
        sLog.AddStrings(sResult);

        sLog.Add('');
        sLog.Add('>>> '+ DateTimeToStr(Now)+': Done "'+ TPath.GetFileNameWithoutExtension( sCmd ) +' '+ sPar +'"' );
        writeln(sLog[ sLog.Count-1 ]);

        sLog.Add('----------' );
        writeln('Enviando e-mail');
        writeln( '----------' );

      end;

      // Limpar result
      sResult.Clear;

    end;

    if SendEmail = true then
    begin
      SendEmail;

      Writeln( 'Relatório enviado para o e-mail' );
    end;

    writeln('Concluído !');

    sLog.SaveToFile(GetLogFilename);

  finally
    sResult.Free;
    sLog.Free;
  end;
end;



{ Início do Programa Principal }
begin
  { Chamadas sucessivas }

  try


    writeln('');
    writeln('TestArchive v1.1');
    writeln('(c) 2022 - Via Regra ');
    writeln('');

    if (not FillCommandParams) then
    begin
      writeln( ' Syntax: ' );
      writeln( ' TestArchive /path:<root destination folder>' );
      writeln( '                      /mask:<file mask to delete>' );
      writeln( '                        /cmd:<calling .rar>' );
      writeln( '                          /cmdpar:<parameter, test integrity>' );
      writeln('');
      writeln( ' Sample: ' );
      writeln( ' TestArchive /path:C:\coding\proj /mask:* /cmd:C:\coding\proj\rar.exe /cmdpar:"t -idp %s"' );
      writeln('');

      // TestArchive /path:C:\1coding\Delphi\TestArchive /mask:*.rar /cmd:C:\1coding\Delphi\TestArchive\rar.exe /cmdpar:"t -idp %s"

      Exit;
    end;

    CallTestIntegrity;

  finally
    sFileList.Free;
  end;

end.
