import strutils,os,times,math,parseopt,parseutils

# Here begins code ported from the original C# kpmml

# -- Filter logic, currently uses globals --

var window1 = newSeq[float32](0)
var window2 = newSeq[float32](0)

var output3: float32 = 0.0
var output2: float32 = 0.0

proc SVF(input: float32, cutoff: float32, typ: uint8): float32 =
  if window1.len >= 2:
    window1.delete(0)
    window2.delete(0)

  var a1, a2: float32
  var output1 = input + output2 - output3

  window1.add(output1.float32)
  for item in window1:
    a1 = max(-150.0, min(150.0, a1 + item))
  output2 = float32((-1) * (1 / (TAU * cutoff) * a1))

  window2.add(output2.float32)
  for item in window2:
    a2 = max(-150.0, min(150.0, a2+ item))
  output3 = float32((-1) * (1 / (TAU * cutoff) * a2))

  if typ == 2:
    return output1
  elif typ == 1:
    return output2
  else:
    return output3

# PORTING ENDS HERE

let notes: seq[tuple[name: string, freq: float32]] = @[("CN",16.35'f32),("CS",17.32'f32),("DN",18.35'f32),("DS",19.45'f32),("E",20.60'f32),("FN",21.83'f32),("FS",23.12'f32),("GN",24.50'f32),("GS",25.96'f32),("AN",27.50'f32),("AS",29.14'f32),("B",30.87'f32),("R",0.0000000001'f32)]

# Tree
# |-- Dependency categorisation [for FM]
#     |-- Channels
#         |-- Channel code

var tree = newSeq[tuple[dlev:uint16,chns:seq[tuple[chan:uint16,lins:seq[string]]]]](0)

var codeMacros = newSeq[tuple[name:string,line:string]](0)

var envdefs = newSeq[tuple[name:string,attk:float32,hold:float32,dcay:float32,isus:bool,susl:float32]](0)
var wavdefs = newSeq[tuple[name:string,wtyp:string,ampl:float32,duty:uint16]](0)
var fmdefs = newSeq[tuple[name:string,o3:bool,cenv:string,mult:uint8,tmod:uint8,tcar:uint8,inch:uint16]](0)

var MATHBITS: uint8 = 32

var SAMPRATE: uint32 = 44100
var FILENAME: string = ""
var TICKRATE: uint16 = 0

var NAME, AUTH: string = ""

proc phelp() =
  echo "HELP UNIMPLEMENTED OH GODS"
  quit(0)

for kind, key, val in getopt():
  case kind
  of cmdArgument:
    FILENAME = key
  of cmdLongOption, cmdShortOption:
    case key
    of "help", "h": phelp()
    of "math", "m": MATHBITS = val.parseUInt().uint8
    of "samp", "samplerate", "s": SAMPRATE = val.parseUint().uint32
  of cmdEnd: echo "what ?"
if FILENAME == "":
  echo "You need to specify a file, titscheese."
  quit(1)

var currBlock: string = "m"

proc processMetaSym(symbol: string) =
  if symbol.startsWith("name="):
    NAME = symbol
    NAME.removePrefix("name="):
  elif symbol.startsWith("author="):
    AUTH = symbol
    AUTH.removePrefix("author=")
  elif symbol.endsWith("hz"):
    var symbolCopy = symbol
    symbolCopy.removeSuffix("hz")
    TICKRATE = symbolCopy.parseUInt().uint16

proc addToLine(input: string, outer: var string) =
  if outer.len == 0:
    outer = input
  else:
    outer = "$1 $2" % [outer, input]
  return

for line in FILENAME.lines:
  var codeLine: string = ""
  var chanNum: uint16 = 0
  var macroName: string = ""
  
  var envName: string = ""

  block deComment:
    if line.startsWith('#') or line.isEmptyOrWhitespace():
      break deComment

    var currSymbol: uint16 = 0
    for symbol in line.split:
      currSymbol.inc

      if symbol.startsWith('#') or symbol.isEmptyOrWhitespace():
        break deComment
      if symbol.startsWith('/'):
        case symbol
        of "/env": currBlock = "e"
        of "/wav": currBlock = "w"
        of "/fm": currBlock = "f"
        of "/mu": currBlock = "c"
        else:
          echo "Invalid block name"
          quit(2)
        break deComment

      case currBlock
      of "m": processMetaSym(symbol)
#      of "e":
#      of "w":
#      of "f":
      of "c":
        if currSymbol == 1 and symbol.startsWith('c'):
          var symbolCopy = symbol
          symbolCopy.removePrefix('c')
          chanNum = symbolCopy.parseUInt().uint16
        elif currSymbol == 1:
          macroName = symbol
        else:
          symbol.addToLine(codeLine)

