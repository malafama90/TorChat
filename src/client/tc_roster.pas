unit tc_roster;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  tc_interface,
  tc_templist;

type
  { TRoster contains all the buddy objects and implements all the boring
  CRUD mechanisms, persisting on disk, etc. Its essentialy an array of
  IBuddy with a few helper methods to manage it. TBuddyList is thread safe.}
  TRoster = class(TTempList, IRoster)
  strict protected
    FOwnID: String;
    FShowMyself: Boolean;
  public
    constructor Create(AClient: IClient); reintroduce;
    procedure SetOwnID(AID: String);
    function OwnID: String;
    function GroupName: String;
    procedure AddBuddy(ABuddy: IBuddy); override;
    procedure RemoveBuddy(ABuddy: IBuddy); override;
    procedure Load;
    procedure Save;
  end;


implementation
uses
  sysutils,
  fpjson,
  jsonparser,
  tc_buddy,
  tc_misc;

{ TRoster }

constructor TRoster.Create(AClient: IClient);
begin
  Inherited Create(AClient);
  FShowMyself := False;
end;

procedure TRoster.SetOwnID(AID: String);
var
  Buddy : IBuddy;
begin
  FOwnID := AID;
  if FShowMyself and (ByID(AID) = nil) then begin
    writeln('TBuddyList.SetOwnID() adding "myself"-buddy ' + AID);
    Buddy := TBuddy.Create(FClient);
    Buddy.InitID(AID);
    Buddy.SetFriendlyName('myself');
    AddBuddy(Buddy);
    Save;
  end
  else begin
    Buddy := ByID(AID);
    if Assigned(Buddy) then
      RemoveBuddy(Buddy);
  end;
end;

function TRoster.OwnID: String;
begin
  Result := FOwnID;
end;

function TRoster.GroupName: String;
begin
  Result := Format('%s (%s)', [FClient.ProfileName, FOwnID]);
end;

procedure TRoster.AddBuddy(ABuddy: IBuddy);
begin
  inherited AddBuddy(ABuddy);
  Save;
  FClient.OnBuddyAdded(ABuddy);
  FClient.OnBuddyStatusChange(ABuddy);
end;

procedure TRoster.RemoveBuddy(ABuddy: IBuddy);
begin
  inherited RemoveBuddy(ABuddy);
  FClient.OnBuddyRemoved(ABuddy);
end;

procedure TRoster.Load;
var
  FS: TFileStream = nil;
  JParser: TJSONParser = nil;
  JList: TJSONArray = nil;
  LastI, I: Integer;
  tc_buddy: IBuddy;
begin
  try
    writeln('TBuddyList.Load()');
    FS := TFileStream.Create(ConcatPaths([FClient.Config.DataDir, 'buddylist.json']), fmOpenRead);
    JParser :=TJSONParser.Create(FS);
    JList := JParser.Parse as TJSONArray;
    LastI := JList.Count - 1;
    for I := 0 to LastI do begin
      try
        tc_buddy := TBuddy.Create(FClient);
        tc_buddy.InitFromJsonObect(JList.Objects[I]); // this may raise exception
        AddBuddy(tc_buddy);
        writeln('TBuddyList.Load() ' + tc_buddy.ID + ' loaded');
      except
        FreeAndNil(tc_buddy);
        writeln('E TBuddyList.Load() error while parsing buddy');
      end;
    end;
  except
    on E: Exception do begin
      WriteLn('W TBuddyList.Load() could not load: ' + E.Message);
    end;
  end;
  if assigned(JList) then FreeAndNil(JList);
  if assigned(JParser) then FreeAndNil(JParser);
  if assigned(FS) then FreeAndNil(FS);
  Save;
end;

procedure TRoster.Save;
var
  Path, FileName, TempName: String;
  Buddy: IBuddy;
  JArr : TJSONArray;
  JData: String;
  FS: TFileStream = nil;
  Success: Boolean;
begin
  writeln('TBuddyList.Save()');
  Success := False;
  Path := FClient.Config.DataDir;
  TempName := ConcatPaths([Path,'_buddylist.json']);
  FileName := ConcatPaths([Path,'buddylist.json']);
  JArr := TJSONArray.Create;

  for Buddy in Self do
    JArr.Add(Buddy.AsJsonObject);

  JData := JArr.FormatJSON([foSingleLineObject]);
  JArr.Free;
  try
    FS := TFileStream.Create(TempName, fmCreate + fmOpenWrite);
    FS.Write(JData[1], Length(JData));
    Success := True;
  except
    on E: Exception do begin
      writeln('E TBuddyList.Save() could not save: ' + E.Message);
    end;
  end;
  if Assigned(FS) then FreeAndNil(FS);

  if Success then begin
    SafeDelete(FileName);
    RenameFile(TempName, FileName);
  end
  else
    SafeDelete(TempName);
end;

end.

