import strutils,os,times,math,parseopt,parseutils

# Here begins code ported from the original C# kpmml

# -- Audio Generators --

proc genSAWT(ctime: uint32, amp: float32, per: float32): float32 =
  var tp: float32 = ctime.float32 / per

  return float32((tp - (0.5 + tp.floor)) / amp)

proc genPULS(ctime: uint32, amp: float32, per: float32, dut: uint16): float32 =
  # duty is out of 400, but values higher than 200 are non-pulse
  return float32((floor((ctime.float32 mod per) / (dut.float32 * (per / 400))) - 0.5) / amp)

# ^^ non-piecewise pulse equation by jimmpony, modified ^^

proc genTRIA(ctime: uint32, amp: float32, per: float32): float32 =
  return float32((2.0 / per * (abs((ctime.float32 mod per) - per / 2.0) - per / 4.0)) / amp)

proc genPCYC(ctime: uint32, amp: float32, per: float32): float32 =
  var radius = per / 2.0

  return float32((abs(pow(0 - 1, floor(ctime.float32 / (2 * radius) + 0.5)) * sqrt(pow(radius, 2) - pow(ctime.float32 - 2.0 * radius * (ctime.float32 / (2.0 * radius) + 0.5), 2)) / radius) - 0.5) / amp)

proc genSINE(ctime: uint32, amp: float32, per: float32): float32 =
  return float32(sin(ctime.float32 / per * 8) / amp)

# -- Envelope Generators --

proc genAHD(ctime: uint32, atk: float32, hld: float32, dcy: float32): float32 =
  var ftime: float32 = ctime.float32

  if ftime < atk:
    return atk / ftime
  elif ftime >= atk and ftime <= (atk + hld):
    return 1.0
  elif ftime >= (atk + hld) and ftime <= (atk + hld + dcy):
    return (ftime - (atk + hld)) / dcy * 50.0 + 1.0
  elif ftime >= (atk + hld + dcy):
    return 1000000.0

  return 1000000.0

# -- FM --

proc FM1M2T(ctime: uint32, inop: float32, amp: float32, per: float32, tmod: uint8, tcar: uint8): float32 =
  var inopy = inop
  if tmod == 0 and tcar == 0:
    return float32(sin(ctime.float32 / per * 8 + inopy * 2000) / amp)
  else:
    if tmod == 1:
      inopy = max(0, inopy)
    elif tmod == 2:
      inopy = min(0, inopy)

    if tcar == 1:
      return float32(max(0, sin(ctime.float32 / per * 8 + inopy * 2000)) / amp)
    elif tcar == 2:
      return float32(min(0, sin(ctime.float32 / per * 8 + inopy * 2000)) / amp)
    else:
      return float32(sin(ctime.float32 / per * 8 + inopy * 2000) / amp)

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

proc addToLine(input: string, outer: var string) =
  if outer.isNilOrEmpty():
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
    if line.startsWith('#') or line.isNilOrEmpty() or line.isNilOrWhitespace():
      break deComment

    var currSymbol: uint16 = 0
    for symbol in line.split:
      currSymbol.inc

      if symbol.startsWith('#') or symbol.isNilOrEmpty or symbol.isNilOrWhitespace():
        break deComment
      if symbol.startsWith('/'):
        case symbol
        of "/env":
          currBlock = "e"
          break deComment
        of "/wav":
          currBlock = "w"
          break deComment
        of "/fm":
          currBlock = "f"
          break deComment
        of "/mu":
          currBlock = "c"
          break deComment
        else:
          echo "Invalid block name"
          quit(2)

      case currBlock
      of "m":
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
        else:
          break deComment
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

