import strutils,os,times,math,parseopt,parseutils,audiogen

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

proc cleanFilter() =
  window1 = newSeq[float32](0)
  window2 = newSeq[float32](0)

let notes: seq[tuple[name: string, freq: float32]] = @[("CN",16.35'f32),("CS",17.32'f32),("DN",18.35'f32),("DS",19.45'f32),("E",20.60'f32),("FN",21.83'f32),("FS",23.12'f32),("GN",24.50'f32),("GS",25.96'f32),("AN",27.50'f32),("AS",29.14'f32),("B",30.87'f32),("R",0.0000000001'f32)]

# Tree
# |-- Dependency categorisation [for FM]
#     |-- Channels
#         |-- Channel code

#2022 update: WHAT THE HELL IS THIS?

#var tree = newSeq[tuple[dlev:uint16,chns:seq[tuple[chan:uint16,lins:seq[string]]]]](0)

var chans = newSeq[seq[string]](0)

var codeMacros = newSeq[tuple[name:string,line:string]](0)

var envdefs = newSeq[tuple[name:string,line:seq[string]]](0)
var wavdefs = newSeq[tuple[name:string,line:seq[string]]](0)
var fmdefs = newSeq[tuple[name:string,line:seq[string]]](0)

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

# why did i put the parser out in global code like this?????????

var push: bool = false
var pushName: string = ""
var pushSeq: seq[string] = @[]

for line in FILENAME.lines:

  if push:
    case currBlock:
    of "e": envdefs.add((name: pushName, line: pushSeq))
    of "w": wavdefs.add((name: pushName, line: pushSeq))
    of "f": fmdefs.add((name:pushName, line: pushSeq))

  push = false
  pushName = ""
  pushSeq = @[]

  var codeLine: string = ""
  var chanNum: int = 0
  var macroName: string = ""

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
      of "e", "w", "f":
        if currSymbol == 1:
          pushName = symbol
          push = true
        else:
          pushSeq.add(symbol)
      of "c":
        if currSymbol == 1 and symbol.startsWith('c'):
          var symbolCopy = symbol
          symbolCopy.removePrefix('c')
          chanNum = symbolCopy.parseInt()
        elif currSymbol == 1:
          macroName = symbol
        else:
          symbol.addToLine(codeLine)
    if currBlock == "c" and macroName.isEmptyOrWhitespace():
      while chanNum > chans.len:
        chans.add(@[])
      chans[chanNum].add(codeLine)
    elif currBlock == "c":
      codeMacros.add((name: macroName, line: codeLine))

