{{
  HTTPServer.spin

  Minimal HTTP request parsing and HTML page building for the config web page - a small GET-returns-a-form,
  POST-saves-the-fields admin page. Deliberately plain/no-frills: no CSS/JS, unquoted HTML attributes (valid HTML5
  when the value has no whitespace/quotes, true for every field here), no percent-decoding (every form field used
  is digits-only - digits are never percent-encoded by a standard form submission).

  Hardware-independent by design, matching DDP_Parser.spin's own stated philosophy ("owns no pins, no SPI, no cog
  of its own"): this object never touches W5200_Driver or Config directly. Spin1 has no object-reference/pointer
  mechanism to safely share a single object instance across files, so Main.spin is the only object that owns the
  real `w5200` and `config` instances and does all the actual socket I/O and config reads/writes - this object
  only parses bytes it's handed and builds bytes to send back, via plain pointers/lengths, the same way
  DDP_Parser.ProcessPacket takes a raw packet pointer instead of owning the socket that received it.

  Field names (plain decimal - digits are never percent-encoded by standard form submission, so no decoding is
  needed). MAC and the DDP port are NOT configurable here (fixed in Main.spin), per user decision:
    ip0..ip3, gw0..gw3, sn0..sn3   - decimal 0-255 each
    p1..p4                          - decimal per-port pixel counts
}}

VAR
  long bufBase, cursor

PUB IsPOST(bufPtr) : isPost
  isPost := (byte[bufPtr][0] == "P" and byte[bufPtr][1] == "O" and byte[bufPtr][2] == "S" and byte[bufPtr][3] == "T")

PUB FindHeaderEnd(bufPtr, len) : idx | i
'' Returns the index just past the blank line ending the HTTP headers (start of any body), or -1 if the full
'' header block hasn't arrived yet.
  idx := -1
  if len < 4
    return
  repeat i from 0 to len - 4
    if byte[bufPtr][i] == 13 and byte[bufPtr][i+1] == 10 and byte[bufPtr][i+2] == 13 and byte[bufPtr][i+3] == 10
      return i + 4
  return -1

PUB GetContentLength(bufPtr, headerEnd) : n | i, j, matched, k, lit
  n := 0
  lit := string("Content-Length:")
  i := 0
  repeat while i < headerEnd - 15
    matched := true
    repeat j from 0 to 14
      if byte[bufPtr][i+j] <> byte[lit][j]
        matched := false
        quit
    if matched
      k := i + 15
      repeat while k < headerEnd and byte[bufPtr][k] == " "
        k++
      n := ParseDecimal(bufPtr + k, headerEnd - k)
      return n
    i++
  return 0

PUB BuildFormPage(destPtr, ipPtr, gwPtr, snPtr, p1, p2, p3, p4) : len
  BeginBuild(destPtr)
  AppendStr(string("HTTP/1.0 200 OK", 13, 10, "Content-Type: text/html", 13, 10, "Connection: close", 13, 10, 13, 10))
  AppendStr(string("<html><body><h1>SanDevicesDDP Config</h1><form method=POST action=/>"))

  AppendStr(string("<p>IP: "))
  AppendOctetField(string("ip0"), byte[ipPtr][0])
  AppendStr(string("."))
  AppendOctetField(string("ip1"), byte[ipPtr][1])
  AppendStr(string("."))
  AppendOctetField(string("ip2"), byte[ipPtr][2])
  AppendStr(string("."))
  AppendOctetField(string("ip3"), byte[ipPtr][3])
  AppendStr(string("</p>"))

  AppendStr(string("<p>Gateway: "))
  AppendOctetField(string("gw0"), byte[gwPtr][0])
  AppendStr(string("."))
  AppendOctetField(string("gw1"), byte[gwPtr][1])
  AppendStr(string("."))
  AppendOctetField(string("gw2"), byte[gwPtr][2])
  AppendStr(string("."))
  AppendOctetField(string("gw3"), byte[gwPtr][3])
  AppendStr(string("</p>"))

  AppendStr(string("<p>Subnet: "))
  AppendOctetField(string("sn0"), byte[snPtr][0])
  AppendStr(string("."))
  AppendOctetField(string("sn1"), byte[snPtr][1])
  AppendStr(string("."))
  AppendOctetField(string("sn2"), byte[snPtr][2])
  AppendStr(string("."))
  AppendOctetField(string("sn3"), byte[snPtr][3])
  AppendStr(string("</p>"))

  AppendStr(string("<p>Pixels per port (J1-J4):<br>"))
  AppendNumField(string("p1"), p1, 3)
  AppendNumField(string("p2"), p2, 3)
  AppendNumField(string("p3"), p3, 3)
  AppendNumField(string("p4"), p4, 3)
  AppendStr(string("</p>"))

  AppendStr(string("<p><input type=submit value=Save></p></form></body></html>"))
  return cursor

PUB BuildSavedPage(destPtr) : len
  BeginBuild(destPtr)
  AppendStr(string("HTTP/1.0 200 OK", 13, 10, "Content-Type: text/html", 13, 10, "Connection: close", 13, 10, 13, 10))
  AppendStr(string("<html><body><h1>Saved</h1><p>Rebooting - reload this page in a few seconds.</p></body></html>"))
  return cursor

PUB ParseForm(bodyPtr, bodyLen, ipPtr, gwPtr, snPtr, p1Ptr, p2Ptr, p3Ptr, p4Ptr) | pos, keyStart, keyLen, valStart, valLen, eqPos, ampPos
'' Overwrites only the fields present in the submitted body - callers should pre-fill the output
'' pointers with current values first, so an omitted field keeps its existing value.
  pos := 0
  repeat while pos < bodyLen
    keyStart := pos
    eqPos := FindChar(bodyPtr, pos, bodyLen, "=")
    if eqPos < 0
      quit
    keyLen := eqPos - keyStart
    valStart := eqPos + 1
    ampPos := FindChar(bodyPtr, valStart, bodyLen, "&")
    if ampPos < 0
      valLen := bodyLen - valStart
      pos := bodyLen
    else
      valLen := ampPos - valStart
      pos := ampPos + 1
    ApplyField(bodyPtr + keyStart, keyLen, bodyPtr + valStart, valLen, ipPtr, gwPtr, snPtr, p1Ptr, p2Ptr, p3Ptr, p4Ptr)

PRI ApplyField(keyPtr, keyLen, valPtr, valLen, ipPtr, gwPtr, snPtr, p1Ptr, p2Ptr, p3Ptr, p4Ptr)
  if KeyIs(keyPtr, keyLen, string("ip0"))
    byte[ipPtr][0] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("ip1"))
    byte[ipPtr][1] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("ip2"))
    byte[ipPtr][2] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("ip3"))
    byte[ipPtr][3] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("gw0"))
    byte[gwPtr][0] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("gw1"))
    byte[gwPtr][1] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("gw2"))
    byte[gwPtr][2] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("gw3"))
    byte[gwPtr][3] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("sn0"))
    byte[snPtr][0] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("sn1"))
    byte[snPtr][1] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("sn2"))
    byte[snPtr][2] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("sn3"))
    byte[snPtr][3] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("p1"))
    long[p1Ptr] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("p2"))
    long[p2Ptr] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("p3"))
    long[p3Ptr] := ParseDecimal(valPtr, valLen)
  elseif KeyIs(keyPtr, keyLen, string("p4"))
    long[p4Ptr] := ParseDecimal(valPtr, valLen)

PRI KeyIs(keyPtr, keyLen, litPtr) : eq | litLen, i
  litLen := strsize(litPtr)
  if litLen <> keyLen
    return false
  repeat i from 0 to keyLen - 1
    if byte[keyPtr][i] <> byte[litPtr][i]
      return false
  return true

PRI FindChar(bufPtr, startPos, endPos, ch) : idx | i
  repeat i from startPos to endPos - 1
    if byte[bufPtr][i] == ch
      return i
  return -1

PRI ParseDecimal(ptr, len) : n | i, c
'' Stops at the first non-digit, so this also works for scanning an open-ended header line
'' (e.g. "Content-Length: 37\r\n...") where len covers everything up to the end of the buffer.
  n := 0
  repeat i from 0 to len - 1
    c := byte[ptr][i]
    if c => "0" and c =< "9"
      n := n*10 + (c - "0")
    else
      quit
  return n

' --- response-building cursor helpers (private scratch state - single response built at a time) ---

PRI BeginBuild(destPtr)
  bufBase := destPtr
  cursor := 0

PRI AppendStr(strPtr) | len
  len := strsize(strPtr)
  bytemove(bufBase + cursor, strPtr, len)
  cursor += len

PRI AppendByte(b)
  byte[bufBase + cursor] := b
  cursor += 1

PRI AppendDecimal(n) | digits[6], count, temp
  if n == 0
    AppendByte("0")
    return
  count := 0
  temp := n
  repeat while temp > 0
    digits[count++] := "0" + (temp // 10)
    temp /= 10
  repeat while count > 0
    count--
    AppendByte(digits[count])

PRI AppendOctetField(namePtr, value)
  AppendStr(string("<input name="))
  AppendStr(namePtr)
  AppendStr(string(" value="))
  AppendDecimal(value)
  AppendStr(string(" size=3> "))

PRI AppendNumField(namePtr, value, sizeAttr)
  AppendStr(string("<input name="))
  AppendStr(namePtr)
  AppendStr(string(" value="))
  AppendDecimal(value)
  AppendStr(string(" size="))
  AppendDecimal(sizeAttr)
  AppendStr(string("> "))
