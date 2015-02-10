;; -*- lisp -*-

;; This file is part of Hyperluminal-mem.
;; Copyright (c) 2013-2015 Massimiliano Ghilardi
;;
;; This library is free software: you can redistribute it and/or
;; modify it under the terms of the Lisp Lesser General Public License
;; (http://opensource.franz.com/preamble.html), known as the LLGPL.
;;
;; This library is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty
;; of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
;; See the Lisp Lesser General Public License for more details.


(in-package :hyperluminal-mem)

(enable-#?-syntax)

(declaim (inline malloc-bytes))
(defun malloc-bytes (n-bytes)
  "Allocate N-BYTES of raw memory and return raw pointer to it.
The obtained memory must be freed manually: call MFREE on it when no longer needed."
  (ffi-mem-alloc n-bytes))


(declaim (inline malloc-words))
(defun malloc-words (n-words)
  "Allocate N-WORDS words of raw memory and return raw pointer to it.
Usually more handy than MALLOC-BYTES since almost all Hyperluminal-MEM functions
count and expect memory lengths in words, not in bytes."
  (declare (type mem-size n-words))
  (malloc-bytes (* n-words +msizeof-word+)))


(declaim (inline mfree))
(defun mfree (ptr)
  "Deallocate a block of raw memory previously obtained with MALLOC-WORDS or MALLOC-BYTES."
  (declare (type maddress ptr))
  (ffi-mem-free ptr))


           
(defun memset-bytes (ptr fill-byte start-byte end-byte)
  (declare (type maddress ptr)
           (type (unsigned-byte 8) fill-byte)
           (type mem-word start-byte end-byte))
  
  (when (> end-byte start-byte)
    #-abcl
    (let ((n-bytes (- end-byte start-byte)))
      (declare (type mem-word n-bytes))
      (when (> n-bytes 32)
        (unless (zerop start-byte) (setf ptr (cffi-sys:inc-pointer ptr start-byte)))
        (osicat-posix:memset ptr fill-byte n-bytes)
        (return-from memset-bytes nil)))

    (let ((i start-byte))
      (declare (type mem-word start-byte))
      (loop while (< i end-byte) do
           (mset-byte ptr i fill-byte)
           (incf i)))))


(defun memset-words (ptr fill-word start-index end-index)
  (declare (optimize (speed 3) (safety 0) (debug 1))
           (type maddress ptr)
           (type mem-word fill-word)
           (type mem-size start-index end-index))

  (symbol-macrolet ((i start-index)
                    (end end-index))
    ;; ARM has no SAP+INDEX*SCALE+OFFSET addressing,
    ;; and 32-bit x86 is register-starved, so this currently leaves x86-64
    #?+(and hlmem/fast-mem x86-64)
    (when (> end i)
      (let ((sap      (the hl-asm:fast-sap (hl-asm:sap=>fast-sap ptr)))
            (bulk-end (mem-size+ i (logand -8 (- end i)))))
        (loop while (< i bulk-end)
           do
             (fast-mset-word fill-word sap i :offset (* 0 +msizeof-word+))
             (fast-mset-word fill-word sap i :offset (* 1 +msizeof-word+))
             (fast-mset-word fill-word sap i :offset (* 2 +msizeof-word+))
             (fast-mset-word fill-word sap i :offset (* 3 +msizeof-word+))
             (fast-mset-word fill-word sap i :offset (* 4 +msizeof-word+))
             (fast-mset-word fill-word sap i :offset (* 5 +msizeof-word+))
             (fast-mset-word fill-word sap i :offset (* 6 +msizeof-word+))
             (fast-mset-word fill-word sap i :offset (* 7 +msizeof-word+))
             (incf-mem-size i 8))

        (loop while (< i end-index)
           do
             (fast-mset-word fill-word sap i)
             (incf i))))
    
    #?-(and hlmem/fast-mem x86-64)
    (when (> end i)
      ;; 32-bit x86 is register-starved
      #-x86
      (let ((bulk-end (the mem-size (+ i (logand -4 (the mem-size (- end-index i)))))))
        (loop while (< i bulk-end)
           do
             (let ((i1 (mem-size+ i 1))
                   (i2 (mem-size+ i 2))
                   (i3 (mem-size+ i 3)))
               (mset-word ptr i  fill-word)
               (mset-word ptr i1 fill-word)
               (mset-word ptr i2 fill-word)
               (mset-word ptr i3 fill-word)
               (incf-mem-size i 4))))
      
      (loop while (< i end-index)
         do
           (mset-word ptr i fill-word)
           (incf-mem-size i)))))



(declaim (inline mzero-bytes))
(defun mzero-bytes (ptr start-byte end-byte)
  (declare (type maddress ptr)
           (type mem-word start-byte end-byte))
  (memset-bytes ptr 0 start-byte end-byte))


#?+(and hlmem/fast-mem x86-64)
(declaim (inline mzero-words))
(defun mzero-words (ptr start-index end-index)
  (declare (type maddress ptr)
           (type mem-size start-index end-index))
  #?-(and hlmem/fast-mem x86-64)
  (when (> end-index start-index)
    (let ((n-words (the mem-word (- end-index start-index))))
      (when (> n-words 32)
        (unless (zerop start-index)
          (setf ptr (cffi-sys:inc-pointer ptr (* start-index +msizeof-word+))))
        (osicat-posix:memset ptr 0 (* n-words +msizeof-word+))
        (return-from mzero-words nil))))

  (memset-words ptr 0 start-index end-index))
  



(defun memcpy-bytes (dst dst-byte src src-byte src-end)
  (declare (type maddress dst src)
           (type mem-word dst-byte src-byte src-end))
  (symbol-macrolet ((si src-byte)
                    (di dst-byte)
                    (end src-end))
    (when (> end si)
      (let ((n-bytes (the mem-word (- end si))))
        #-abcl
        (when (> n-bytes 32)
          (unless (zerop di) (setf dst (cffi-sys:inc-pointer dst di)))
          (unless (zerop si) (setf src (cffi-sys:inc-pointer src si)))
          (osicat-posix:memcpy dst src n-bytes)
          (return-from memcpy-bytes nil))
        
        (dotimes (i n-bytes)
          (mset-byte dst (mem-size+ i di)
                     (mget-byte src (mem-size+ i si))))))))


(defun memcpy-words (dst dst-index src src-index src-end)
  (declare (type maddress dst src)
           (type mem-size dst-index src-index src-end))

  (symbol-macrolet ((si src-index)
                    (di dst-index)
                    (end src-end))
    (when (> end si)
      #?-(and hlmem/fast-mem x86-64)
      #-abcl
      (let ((n-words (mem-size- end si)))
        (when (> n-words 128)
          (unless (zerop di) (setf dst (cffi-sys:inc-pointer dst di)))
          (unless (zerop si) (setf src (cffi-sys:inc-pointer src si)))
          (osicat-posix:memcpy dst src (* n-words +msizeof-word+))
          (return-from memcpy-words nil)))

      
      #?+(and hlmem/fast-mem x86-64)
      (let ((dsap (the hl-asm:fast-sap (hl-asm:sap=>fast-sap dst)))
            (ssap (the hl-asm:fast-sap (hl-asm:sap=>fast-sap src)))
            (bulk-end (if (>= end 6) (- end 6) 0)))
        (loop while (< si bulk-end)
           do
             (let ((v0 (fast-mget-word ssap si :offset (* 0 +msizeof-word+)))
                   (v1 (fast-mget-word ssap si :offset (* 1 +msizeof-word+)))
                   (v2 (fast-mget-word ssap si :offset (* 2 +msizeof-word+)))
                   (v3 (fast-mget-word ssap si :offset (* 3 +msizeof-word+)))
                   (v4 (fast-mget-word ssap si :offset (* 4 +msizeof-word+)))
                   (v5 (fast-mget-word ssap si :offset (* 5 +msizeof-word+))))
               (fast-mset-word v0 dsap di :offset (* 0 +msizeof-word+))
               (fast-mset-word v1 dsap di :offset (* 1 +msizeof-word+))
               (fast-mset-word v2 dsap di :offset (* 2 +msizeof-word+))
               (fast-mset-word v3 dsap di :offset (* 3 +msizeof-word+))
               (fast-mset-word v4 dsap di :offset (* 4 +msizeof-word+))
               (fast-mset-word v5 dsap di :offset (* 5 +msizeof-word+)))
             (incf-mem-size si 6)
             (incf-mem-size di 6)))

      (loop while (< si end)
         do
           (mset-word dst di (mget-word src si))
           (incf-mem-size si)
           (incf-mem-size di)))))



