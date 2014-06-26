;; -*- Lisp -*-

(defpackage :dump-packets
  (:use :cl))

(in-package :dump-packets)

(ql:quickload :binary-types)
(ql:quickload :alexandria)

(setf binary-types:*endian* :little-endian)

(defun decode-integer (vector)
  (binary-types:with-binary-input-from-vector (x vector)
    (binary-types:read-binary 'binary-types:s32 x)))

(defparameter *header-length* 24)
(defparameter *packet-size* 76)
(defparameter *data-offset* 30)
(defparameter *integer-size* 4)

(defun check-file (pathname)
  (loop with data = (alexandria:read-file-into-byte-vector pathname)
        with expected = 0
        for pos from *header-length* by *packet-size* below (length data)
        for actual = (decode-integer (subseq data (+ pos *data-offset*) (+ pos *data-offset* *integer-size*)))
        when (/= expected actual)
          do (format t "at ~A expected ~A got ~A~%" pos expected actual)
        do (setf expected (1+ actual))))
