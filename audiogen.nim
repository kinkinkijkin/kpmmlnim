import math

# -- Audio Generators --

proc genSAWT*(ctime: uint32, amp: float32, per: float32): float32 =
  var tp: float32 = ctime.float32 / per

  return float32((tp - (0.5 + tp.floor)) / amp)

proc genPULS*(ctime: uint32, amp: float32, per: float32, dut: uint16): float32 =
  # duty is out of 400, but values higher than 200 are non-pulse
  return float32((floor((ctime.float32 mod per) / (dut.float32 * (per / 400))) - 0.5) / amp)

# ^^ non-piecewise pulse equation by jimmpony, modified ^^

proc genTRIA*(ctime: uint32, amp: float32, per: float32): float32 =
  return float32((2.0 / per * (abs((ctime.float32 mod per) - per / 2.0) - per / 4.0)) / amp)

proc genPCYC*(ctime: uint32, amp: float32, per: float32): float32 =
  var radius = per / 2.0

  return float32((abs(pow(0 - 1, floor(ctime.float32 / (2 * radius) + 0.5)) * sqrt(pow(radius, 2) - pow(ctime.float32 - 2.0 * radius * (ctime.float32 / (2.0 * radius) + 0.5), 2)) / radius) - 0.5) / amp)

proc genSINE*(ctime: uint32, amp: float32, per: float32): float32 =
  return float32(sin(ctime.float32 / per * 8) / amp)

# -- Envelope Generators --

proc genAHD*(ctime: uint32, atk: float32, hld: float32, dcy: float32): float32 =
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

proc FM1M2T*(ctime: uint32, inop: float32, amp: float32, per: float32, tmod: uint8, tcar: uint8): float32 =
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
