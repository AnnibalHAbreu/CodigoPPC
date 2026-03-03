TYPE UN_Real_to_Word_array :
UNION
	RealArr  : ARRAY[1..15] OF REAL;   // 60 bytes
    WordArr  : ARRAY[1..30] OF WORD;   // 60 bytes
END_UNION
END_TYPE
