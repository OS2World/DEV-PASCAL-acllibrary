Unit ACLString;

Interface

uses
  SysUtils;

{
  AString: A length-safe string class. Internally maintains
  a length as well as a zero terminator, so very fast for concatenation

  There is no point in this class for Delphi, which has a fast
  reference counted string type built in.

  For extra safety it explicitly checks that this is a valid instance of
  AString on every method call (using an internal magic number)
  You can also call the global procedure
    CheckAllAStringsDestroyed
  at the end of the program to make sure there are no memory leaks
  due to AStrings not being destroyed.

  V1.2 28/6/00
    Added ReadLn and WriteLn methods (for text files)
    Added Character index property
  V1.1 27/6/00
    Added:
      Delete - delete a seciton of string
      Assign methods
      AsString property
      CharPosition function
      ExtractNextValue method
        This method, unlike my original string version, does not
        alter the main string. Rather it takes and increments
        a starting position.

  V1.0
    Completed basic functionality
    Used in NewView for decoding help topics. Fast!
}

type
  EAStringError = class( Exception );
  EAStringIndexError = class( EAStringError );

  TAString = class
  private
    function GetIsEmpty: boolean;
  protected
    _S: PChar;
    _Length: longint;
    _MagicNumber: longword;
    procedure CheckSize( const NeededLength: longint );
    procedure AddData( const Data: pointer; const DataLength: longint );
    procedure Initialise;

    function ValidIndex( const Index: longint ): boolean;
    procedure CheckIndex( const Index: longint );
    function GetAsString: string;

    procedure SetLength( NewLength: longint );

    function GetChar( Index: longint ): Char;
    procedure SetChar( Index: longint;
                       const Value: Char );

  public

    constructor Create;
    constructor CreateFrom( const S: String );
    constructor CreateFromPChar( const S: PChar );
    constructor CreateFromPCharLen( const S: PChar; const Len: longint );
    constructor CreateCopy( const S: TAString );

    // Create a AString from the given PChar and
    // dispose of the PChar. Useful for using when you can only
    // get a PChar as a newly allocated string (e.g TMemo.Lines.GetText)
    constructor CreateFromPCharWithDispose( const S: PChar );

    destructor Destroy; override;

    // Modifications
    procedure Assign( const S: TAString );
    procedure AssignString( const S: string );
    procedure AssignPChar( const S: PChar );
    procedure AssignPCharLen( const S: PChar; const Len: longint );

    procedure Add( const S: TAString );
    procedure AddString( const S: string );
    procedure AddPChar( const S: PChar );
    procedure AddPCharLen( const S: PChar; const Len: longint );

    procedure Trim;
    procedure TrimChar( CharToTrim: Char );
    procedure Delete( const StartingFrom: longint;
                      const LengthToDelete: longint );
    procedure Clear;

    // Properties
    property AsPChar: PChar read _S;
    property AsString: string read GetAsString;
    property Character[ Index: longint ]: Char read GetChar write SetChar; default;
    property Length: longint read _Length write SetLength;
    property IsEmpty: boolean read GetIsEmpty;

    // Queries
    function CharPosition( const StartingFrom: longint;
                           const CharToFind: Char ): longint;

    function SameAs( const S: String ): boolean;

    // Extract the next value seperated by seperator
    // starting at StartingFrom (zero based index!)
    procedure ExtractNextValue( Var StartingFrom: longint;
                                ExtractTo: TAString;
                                const Seperator: Char );
    procedure GetRightFrom( const StartingFrom: longint;
                            Dest: TAString );
    procedure GetLeft( const Count: longint;
                       Dest: TAString );
    procedure GetRight( const Count: longint;
                        Dest: TAString );
    procedure ParseKeyValuePair( KeyName: TAString;
                                 KeyValue: TAString;
                                 Seperator: Char );

    // Make sure the string can contain at least MaxLength chars
    // Use before passing AsPChar to a function that writes a PChar
    procedure SetMaxLength( MaxLength: longint );

    // Read a line from the given file. Line must end
    // with #13 #10. ( Single #13 or #10 not recognised )
    procedure ReadLn( Var TheFile: TextFile );
    procedure WriteLn( Var TheFile: TextFile );
  end;

// call this to be sure all AStrings have been destroyed.
procedure CheckAllAStringsDestroyed;

Implementation

uses
  ACLUtility, ACLPCharUtility;

const
  GlobalAStringCreatedCount: longint = 0;
  GlobalAStringDestroyedCount: longint = 0;

const
  MagicConstant = $cabba9e;

procedure CheckAllAStringsDestroyed;
begin
  if GlobalAStringCreatedCount > GlobalAStringDestroyedCount then
    raise Exception.Create( 'Not all AStrings have been destroyed ('
                            + IntToStr( GlobalAStringCreatedCount )
                            + ' created, '
                            + IntToStr( GlobalAStringDestroyedCount )
                            + ' destroyed). Possible memory leak.' );
end;

procedure CheckValid( const S: TAString );
var
  IsValid: boolean;
begin
  try
    IsValid:= S._MagicNumber = MagicConstant;
  except
    IsValid:= false;
  end;
  if not IsValid then
    raise Exception.Create( 'Reference to invalid AString' );
end;

constructor TAString.Create;
begin
  inherited Create;
  Initialise;
end;

procedure TAString.Initialise;
begin
  inc( GlobalAStringCreatedCount );
  _S:= StrAlloc( 16 );
  _MagicNumber:= MagicConstant;
  Clear;
end;

constructor TAString.CreateFrom( const S: String );
begin
  Initialise;
  AssignString( S );
end;

constructor TAString.CreateFromPChar( const S: PChar );
begin
  Initialise;
  AssignPChar( S );
end;

constructor TAString.CreateFromPCharLen( const S: PChar; const Len: longint );
begin
  Initialise;
  AssignPCharLen( S, Len );
end;

constructor TAString.CreateFromPCharWithDispose( const S: PChar );
begin
  Initialise;
  AddPChar( S );
  StrDispose( S );
end;

constructor TAString.CreateCopy( const S: TAString );
begin
  Initialise;
  Assign( S );
end;

destructor TAString.Destroy;
begin
  inc( GlobalAStringDestroyedCount );
  StrDispose( _S );
  _MagicNumber:= 0;
  inherited Destroy;
end;

procedure TAString.CheckSize( const NeededLength: longint );
var
  temp: PChar;
  NewBufferSize: longint;
  CurrentBufferSize: longint;
begin
  CurrentBufferSize:= StrBufSize( _S );
  if NeededLength + 1 > CurrentBufferSize then
  begin
    // allocate new buffer, double the size...
    NewBufferSize:= CurrentBufferSize * 2;
    // or if that's not enough...
    if NewBufferSize < NeededLength + 1 then
      // double what we are going to need
      NewBufferSize:= NeededLength * 2;

    temp:= StrAlloc( NewBufferSize );

    MemCopy( _S,
             Temp,
             _Length + 1 );

    StrDispose( _S );
    _S:= temp;
  end;
end;

procedure TAString.Clear;
begin
  CheckValid( self );
  _Length:= 0;
  _S[ 0 ]:= #0;
end;

procedure TAString.AddData( const Data: pointer; const DataLength: longint );
begin
  if DataLength = 0 then
    exit;
  CheckSize( _Length + DataLength );
  MemCopy( Data, _S + _Length, DataLength );
  inc( _Length, DataLength );
  _S[ _Length ]:= #0;
end;

procedure TAString.Add( const S: TAString );
begin
  CheckValid( self );
  CheckValid( S );
  AddData( S._S, S.Length );
end;

procedure TAString.AddPChar( const S: PChar );
begin
  CheckValid( self );
  AddData( S, StrLen( S ) );
end;

procedure TAString.AddString( const S: string );
begin
  CheckValid( self );
{$ifdef os2}
  AddData( Addr( S ) + 1, System.Length( S ) );
{$else}
  AddData( PChar( S ), System.Length( S ) );
{$endif}
end;

procedure TAString.TrimChar( CharToTrim: Char );
var
  StartP: PChar;
  EndP: PChar;
  C: Char;
begin
  CheckValid( self );
  if _Length = 0 then
    exit;
  StartP:= _S;
  EndP:= _S + Length;

  while StartP < EndP do
  begin
    C:= StartP^;
    if C <> CharToTrim then
      break;
    inc( StartP );
  end;
  // StartP now points to first non-space char

  while EndP > StartP do
  begin
    dec( EndP );
    C:= EndP^;
    if C <> CharToTrim then
    begin
      inc( EndP );
      break;
    end;
  end;
  // EndP now points to one byte past last non-space char

  _Length:= PCharDiff( EndP, StartP );

  if _Length > 0 then
    if StartP > _S then
      MemCopy( StartP, _S, _Length );

  _S[ _Length ]:= #0;

end;

procedure TAString.ExtractNextValue( Var StartingFrom: longint;
                                     ExtractTo: TAString;
                                     const Seperator: Char );
var
  NextSeperatorPosition: longint;
begin
  CheckValid( self );
  CheckValid( ExtractTo );

  ExtractTo.Clear;
  if StartingFrom >= Length then
    exit;
  NextSeperatorPosition:= CharPosition( StartingFrom,
                                        Seperator );
  if NextSeperatorPosition > -1 then
  begin
    ExtractTo.AddData( _S + StartingFrom,
                       NextSeperatorPosition - StartingFrom );
    StartingFrom:= NextSeperatorPosition + 1;
  end
  else
  begin
    ExtractTo.AddData( _S + StartingFrom,
                       Length - StartingFrom );
    StartingFrom:= Length;
  end;
  ExtractTo.Trim;

end;

procedure TAString.Assign( const S: TAString );
begin
  Clear;
  Add( S );
end;

procedure TAString.AssignPChar( const S: PChar);
begin
  Clear;
  AddPChar( S );
end;

procedure TAString.AssignPCharLen( const S: PChar; const Len: longint );
begin
  Clear;
  AddPCharLen( S, Len );
end;

procedure TAString.AssignString( const S: string );
begin
  Clear;
  AddString( S );
end;

function TAString.CharPosition( const StartingFrom: longint;
                                const CharToFind: Char ): longint;
var
  StartP: PChar;
  P: PChar;
  EndP: PChar;
  C: Char;
begin
  CheckValid( self );
  Result:= -1;
  if not ValidIndex( StartingFrom ) then
    exit;
  StartP:= _S + StartingFrom;
  EndP:= _S + Length;
  P:= StartP;

  while P < EndP do
  begin
    C:= P^;
    if C = CharToFind then
    begin
      Result:= PCharDiff( p, _S );
      break;
    end;
    inc( P );
  end;
end;

procedure TAString.Delete( const StartingFrom: longint;
                           const LengthToDelete: longint );
var
  StartP: PChar;
  EndP: PChar;
  SizeToCopy: longint;
begin
  if not ValidIndex( StartingFrom ) then
    exit;
  if LengthToDelete = 0 then
    exit;

  StartP:= _S + StartingFrom;
  if StartingFrom + LengthToDelete >= Length then
  begin
    SetLength( StartingFrom );
    exit;
  end;
  EndP:= _S + StartingFrom + LengthToDelete;
  SizeToCopy:= Length - ( StartingFrom + LengthToDelete );
  MemCopy( EndP, StartP, SizeToCopy );
  SetLength( Length - LengthToDelete );
end;

function TAString.ValidIndex( const Index: longint ): boolean;
begin
  Result:= ( Index >= 0 ) and ( Index < Length );
end;

function TAString.GetAsString: string;
begin
  CheckValid( self );
{$ifdef os2}
  Result:= StrPas( _S );
{$else}
  Result:= _S;
{$endif}
end;

procedure TAString.SetLength( NewLength: longint );
begin
  CheckValid( self );
  if NewLength < 0 then
    exit;
  CheckSize( NewLength );
  _Length:= NewLength;
  _S[ _Length ]:= #0;

end;

procedure TAString.ReadLn( var TheFile: TextFile );
Var
  C: Char;
  FoundCR: boolean;
Begin
  CheckValid( self );
  Clear;
  FoundCR:= false;
  while not eof( TheFile ) do
  begin
    Read( TheFile, C );
    if ( C = #10 ) then
    begin
      if FoundCR then
        exit; // reached end of line
    end
    else
    begin
      if FoundCR then
        // last CR was not part of CR/LF so add to string
        AddString( #13 );
    end;
    FoundCR:= ( C = #13 );
    if not FoundCR then // don't handle 13's till later
    begin
      AddString( C );
    end;
  end;

  if FoundCR then
    // CR was last char of file, but no LF so add to string
    AddString( #13 );

end;

procedure TAString.WriteLn( var TheFile: TextFile );
var
  P: PChar;
  EndP: PChar;
  C: Char;
begin
  CheckValid( self );

  P:= _S;
  EndP:= _S + Length;

  while P < EndP do
  begin
    C:= P^;
    Write( TheFile, C );
    inc( P );
  end;
  Write( TheFile, #13 );
  Write( TheFile, #10 );
end;

function TAString.GetChar( Index: longint ): Char;
begin
  CheckValid( self );
  CheckIndex( Index );
  Result:= _S[ Index ];
end;

procedure TAString.SetChar( Index: longint;
                            const Value: Char );
begin
  CheckValid( self );
  CheckIndex( Index );
  _S[ Index ]:= Value;
end;

procedure TAString.CheckIndex( const Index: longint );
begin
  if not ValidIndex( Index ) then
    raise EAStringIndexError( 'Index '
                              + IntToStr( Index )
                              + ' is not in valid range ( 0 - '
                              + IntToStr( Length - 1 )
                              + ') for string' );

end;

procedure TAString.ParseKeyValuePair( KeyName: TAString;
                                      KeyValue: TAString;
                                      Seperator: Char );
var
  Position: longint;
begin
  CheckValid( self );
  Position:= 0;
  ExtractNextValue( Position, KeyName, Seperator );
  GetRightFrom( Position, KeyValue );
end;


procedure TAString.GetLeft( const Count: longint;
                            Dest: TAString );
begin
  CheckValid( self );
  Dest.Clear;
  if Count >= Length then
    Dest.Assign( self )
  else if Count > 0 then
    Dest.AddData( _S, Count );
end;

procedure TAString.GetRight( const Count: longint;
                             Dest: TAString );
begin
  CheckValid( self );
  Dest.Clear;
  if Count >= Length then
    Dest.Assign( self )
  else if Count > 0 then
    Dest.AddData( _S + Length - Count - 1, Count );
end;

procedure TAString.GetRightFrom( const StartingFrom: longint;
                                 Dest: TAString );
begin
  CheckValid( self );
  Dest.Clear;
  if StartingFrom <= 0  then
    Dest.Assign( self )
  else if StartingFrom < Length then
    Dest.AddData( _S + StartingFrom, Length - StartingFrom );
end;

function TAString.SameAs( const S: String ): boolean;
begin
  CheckValid( self );
{$ifdef os2}
  if Length > 255 then
  begin
    Result:= false;
    exit;
  end;
  Result:= StrIComp( _S, Addr( S ) + 1 ) = 0;
{$else}
  Result:= StrIComp( _S, PChar( S ) ) = 0;
{$endif}

end;

function TAString.GetIsEmpty: boolean;
begin
  CheckValid( self );
  Result:= Length = 0;
end;

procedure TAString.Trim;
begin
  CheckValid( self );
  TrimChar( #32 );
end;

procedure TAString.SetMaxLength( MaxLength: longint );
begin
  CheckValid( self );
  CheckSize( MaxLength );
end;

procedure TAString.AddPCharLen( const S: PChar; const Len: longint );
begin
  CheckValid( self );
  AddData( S, Len );
end;

Initialization
End.
