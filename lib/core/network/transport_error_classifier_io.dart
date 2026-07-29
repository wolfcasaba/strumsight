import 'dart:io';

bool isTlsTransportError(Object? error) => error is HandshakeException;

bool isConnectionTransportError(Object? error) => error is SocketException;
