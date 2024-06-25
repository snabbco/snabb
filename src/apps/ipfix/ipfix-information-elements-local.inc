6,tcpControlBitsReduced,unsigned8,,,,,,,,[RFC5102],,2013-02-18
2946:100,dnsFlagsCodes,unsigned16,,,,,,,,,
2946:101,dnsQuestionCount,unsigned16,,,,,,,,,
2946:102,dnsAnswerCount,unsigned16,,,,,,,,,
2946:103,dnsQuestionName,octetArray,Domain name in uncompressed on-the-wire encoding,,,,,,,,
2946:104,dnsQuestionType,unsigned16,,,,,,,,,
2946:105,dnsQuestionClass,unsigned16,,,,,,,,,
2946:106,dnsAnswerName,octetArray,Domain name in uncompressed on-the-wire encoding,,"In case of a CNAME chain, 
this is the name of the first non-CNAME answer record or the name of the last CNAME record",,,,,,
2946:107,dnsAnswerType,unsigned16,,,,,,,,,
2946:108,dnsAnswerClass,unsigned16,,,,,,,,,
2946:109,dnsAnswerTtl,unsigned32,,,,,,,,,
2946:110,dnsAnswerRdata,octetArray,"On-the-wire encoding of the answer record's rdata section. For well-known record types, 
compressed domain names have been replaced with their uncompressed counterparts",,,,,,,,
2946:111,dnsAnswerRdataLen,unsigned16,,,,,,,,,
39499:338,fmTlsSNI,string,DNS name from the TLS Server Name Indication extension,,,,,,,,
39499:339,fmTlsSNILength,unsigned16,Length of tlsSNI in bytes,,,,,,,,
39499:1,fmHttpRequestHost,string,,,,,,,,,,
39499:2,fmHttpRequestTarget,string,,,,,,,,,,
39499:4,fmHttpRequestMethod,unsigned16,"Bit mask of HTTP request types
GET     0x0001
POST    0x0002
HEAD    0x0004
PUT     0x0008
OPTIONS 0x0010
DELETE  0x0020
TRACE   0x0040
PATCH   0x0080
CONNECT 0x0100
SSL     0x0200
",,,,,,,,,
