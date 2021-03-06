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


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;    boxed    STRING. uses UTF-8 to reduce memory usage                   ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(enable-#?-syntax)


(declaim (inline msize-box/string-utf-8))

(defun msize-box/string-utf-8 (index string)
  "Return the number of words needed to store STRING in memory, not including BOX header."
  (declare (optimize (speed 3) (safety 0) (debug 1))
           (type string string)
           (type mem-size index))

  #?+hlmem/character=utf-8
  (let ((n-bytes (length string)))
    ;; +1 to store N-CHARS prefix: number of codepoints is not known yet,
    ;; but it's a mem-int so it consumes 1 word.
    (mem-size+ index 1 (ceiling n-bytes +msizeof-word+)))
  
  #?-hlmem/character=utf-8
  (let ((n-bytes 0))
    (declare (type ufixnum n-bytes))

    (macrolet
        ((%count-utf-8-bytes ()
           `(loop for ch across string
               for code = (char-code ch)
               do
                 (incf (the fixnum n-bytes)

                       ;; support UTF-16 strings. Used at least by CMUCL and ABCL
                       #?+hlmem/character=utf-16
                       (cond
                         ((<= code #x7F) 1)
                         ((<= code #x7FF) 2)
                         ((<= #xD800 code #xDBFF) 4) ;; high surrogate
                         ((<= #xDC00 code #xDFFF) 0) ;; low surrogate, space included above
                         (t 3))

                       ;; easier, strings contain Unicode codepoints
                       #?-hlmem/character=utf-16
                       (cond
                         ((<= code #x7F) 1)
                         ((<= code #x7FF) 2)
                         ((<= code #xFFFF) 3)
                         (t 4))))))
      (cond
        ((typep string '(simple-array character)) (%count-utf-8-bytes))
        #?-hlmem/base-char<=ascii ;; if base-char<=ascii, we write an ASCII string
        ((typep string '(simple-array base-char)) (%count-utf-8-bytes))
        (t                                        (%count-utf-8-bytes))))

    ;; +1 to store N-CHARS prefix
    (mem-size+ index 1 (ceiling n-bytes +msizeof-word+))))






(declaim (inline %mwrite-string-utf-8))

#?+hlmem/character=utf-8
(defun %mwrite-string-utf-8 (ptr index end-index string n-chars)
  "Write characters from string STRING to the memory starting at (PTR+INDEX).
Return the number of words actually written.

ABI: characters will be stored using UTF-8 encoding."
  (declare (optimize (speed 3) (safety 0) (debug 1))
           (type maddress ptr)
           (type mem-size index end-index)
           (type string string)
           (type ufixnum n-chars))

  (check-mem-overrun ptr index end-index (fixnum+ 1 (ceiling n-chars +msizeof-word+)))

  ;; we will write n-codepoints later
  (let ((save-index index)
        (n-codepoints 0))
    (declare (type mem-size n-codepoints))
    (incf-mem-size index)

    (macrolet
        ((%utf-8-byte (ch)
           (with-gensym code
             `(let ((,code (char-code ,ch)))
                (incf n-codepoints (if (%utf-8-is-first-byte? ,code) 1 0))
                (the (unsigned-byte 8) ,code))))
         
         (%utf-8-chars-to-word (&rest chars)
           `(logior
             ,@(loop for ch in chars
                  for shift = 0 then (fixnum+ shift 8)
                  collect `(ash (%utf-8-byte ,ch) ,shift))))

         (%utf-8-string-chars-to-word (char-func start-offset)
           `(%utf-8-chars-to-word
             ,@(loop for i below +msizeof-word+
                  collect `(,char-func string (the ufixnum (+ ,start-offset ,i))))))
         
         (%mwrite-utf-8-words-unrolled (char-func)
           `(let ((i 0)
                  (bulk-end (fixnum- n-chars +msizeof-word+)))
              (declare (type ufixnum i))
              (loop while (< i bulk-end)
                 do
                   (let ((word (the mem-word (%utf-8-string-chars-to-word ,char-func i))))
                     (mset-word ptr index word)
                     (incf i +msizeof-word+)
                     (incf-mem-size index)))
              (when (< i n-chars)
                (let ((word 0)
                      (shift 0))
                  (declare (type mem-word word)
                           (type (integer 0 #.+mem-word/bits+) shift))
                  (loop
                     while (< i n-chars)
                     do
                       (setf word (logior word
                                          (the mem-word
                                               (ash (%utf-8-byte (,char-func string i)) shift))))
                       (incf i)
                       (incf shift 8))
                  (mset-word ptr index word)
                  (incf-mem-size index)))))

         (%mwrite-utf-8-words (char-func)
           `(let ((i 0))
              (declare (type ufixnum i))
              (loop while (< i n-chars)
                 do
                   (let ((end (min +msizeof-word+ n-chars))
                         (word 0)
                         (shift 0))
                     (declare (type mem-word word)
                              (type (integer 0 #.+mem-word/bits+) shift))
                     (loop while (< i end)
                        do
                          (setf word (logior word
                                             (the mem-word
                                                  (ash (%utf-8-byte (,char-func string i)) shift))))
                          (incf i)
                          (incf shift 8))
                     (mset-word ptr index word)
                     (incf-mem-size index))))))

      
      (cond
        ((typep string '(simple-array character)) (%mwrite-utf-8-words-unrolled schar))
        #?-hlmem/base-char<=ascii ;; if base-char<=ascii, we write an ASCII string instead
        ((typep string '(simple-array base-char)) (%mwrite-utf-8-words-unrolled schar))
        (t                                        (%mwrite-utf-8-words           char))))

    (mset-int ptr save-index n-codepoints)
    index))
  


#?-hlmem/character=utf-8
(defun %mwrite-string-utf-8 (ptr index end-index string n-chars)
  "Write characters from string STRING to the memory starting at (PTR+INDEX).
Return the number of words actually written.

ABI: characters will be stored using UTF-8 encoding."
  (declare (optimize (speed 3) (safety 0) (debug 1))
           (type maddress ptr)
           (type mem-size index end-index)
           (type string string)
           (type ufixnum n-chars))

  (let ((save-index index)
        (i 0)
        #?+hlmem/character=utf-16 (n-codepoints 0)
        (word 0)
        (word-bits 0)
        (word-bits-left +mem-word/bits+))
    (declare (type mem-size save-index)
             (type fixnum i #?+hlmem/character=utf-16 n-codepoints)
             (type (integer 0 #.(1- +mem-word/bits+)) word-bits)
             (type (integer 1 #.+mem-word/bits+) word-bits-left))

    (incf-mem-size index) ;; we will store n-codepoints at save-index later
    
    (macrolet
        ((%mwrite-utf-8-words (char-func)
           `(loop while (< i n-chars)
               do
                 (let ((code (char-code (,char-func string i))))
                   (incf (the fixnum i))

                   ;; if strings are UTF-16, skip naked (and invalid) low surrogates
                   (when #?+hlmem/character=utf-16 (not (%code-is-low-surrogate code))
                         #?+hlmem/character=utf-16 t
                                                   
                     (multiple-value-bind (next next-bits)
                         (%codepoint->utf-8-word

                          ;; support UTF-16 strings.
                          #?+hlmem/character=utf-16
                          (%utf-16->codepoint code string ,char-func i n-chars)

                          #?-hlmem/character=utf-16
                          code)

                       (declare (type mem-word word next)
                                (type (integer 0 32) next-bits))

                       #?+hlmem/character=utf-16
                       (incf n-codepoints)
                       
                       (setf word (logior word (logand +mem-word/mask+ (ash next word-bits)))
                             word-bits-left (- +mem-word/bits+ word-bits))
              
                       (when (>= next-bits word-bits-left)
                         (check-mem-overrun ptr index end-index 1)
                         (mset-word ptr index word)
                         (setf index     (mem-size+1 index)
                               word      (ash next (- word-bits-left))
                               word-bits (- next-bits word-bits-left)
                               next      0
                               next-bits 0))
                       
                       (incf word-bits next-bits)))))))

      (cond
        ((typep string '(simple-array character)) (%mwrite-utf-8-words schar))
        #?-hlmem/base-char<=ascii ;; if base-char<=ascii, we write an ASCII string instead
        ((typep string '(simple-array base-char)) (%mwrite-utf-8-words schar))
        (t                                        (%mwrite-utf-8-words  char))))

    (unless (zerop word-bits)
      (check-mem-overrun ptr index end-index 1)
      (mset-word ptr index word)
      (incf-mem-size index))

    (mset-int ptr save-index
              #?+hlmem/character=utf-16 n-codepoints
              #?-hlmem/character=utf-16 n-chars)

    index))



(defun mwrite-box/string-utf-8 (ptr index end-index string)
  "write STRING into the memory starting at (+ PTR INDEX).
Assumes BOX header is already written.

ABI: writes string length as mem-int, followed by packed array of UTF-8 encoded characters"
  (declare (type maddress ptr)
           (type mem-size index)
           (type string string))

  (let* ((n-chars (length string))
         (min-n-words (mem-size+1 (ceiling n-chars +msizeof-word+))))
    
    (check-mem-overrun ptr index end-index min-n-words)

    (%mwrite-string-utf-8 ptr index end-index string n-chars)))


(declaim (inline %mread-string-utf-8))

#?+hlmem/character=utf-8
(defun %mread-string-utf-8 (ptr index end-index n-codepoints)
  (declare (type maddress ptr)
           (type mem-size index end-index)
           (type ufixnum n-codepoints))

  (let ((i-codepoints 0)
        (n-bytes 0)
        (word 0)
        (word-n-bytes 0)
        (result (make-array n-codepoints :element-type 'character :adjustable t :fill-pointer 0)))
    
    (declare (type ufixnum i-codepoints)
             (type utf8-n-bytes n-bytes)
             (type mem-word word)
             (type word-n-bytes word-n-bytes))

    (loop while (and (< index end-index) (< i-codepoints n-codepoints))
       do
         (when (zerop word-n-bytes)
           (setf word (mget-word ptr index)
                 word-n-bytes +msizeof-word+)
           (incf-mem-size index))

         (let* ((byte (logand word #xFF))
                (new-n-bytes (%utf-8-first-byte->length byte)))
           (declare (type utf8-n-bytes new-n-bytes))
           
           (setf word (ash word -8))
           (decf word-n-bytes)

           (break)
           
           (if (zerop n-bytes)
               ;; expecting a first-byte
               (if (zerop new-n-bytes)
                   ;; found a continuation byte
                   (invalid-utf8-error byte)
                   (setf n-bytes (1- new-n-bytes)))
               ;; expecting a continuation byte
               (if (zerop new-n-bytes)
                   ;; found a continuation byte
                   (decf n-bytes)
                   (invalid-utf8-continuation-error byte)))

           (vector-push-extend (code-char byte) result)
           
           (when (zerop n-bytes)
             (incf i-codepoints))))
    
    (values result index)))


#?-hlmem/character=utf-8
(defun %mread-string-utf-8 (ptr index end-index n-codepoints)
  (declare (type maddress ptr)
           (type mem-size index end-index)
           (type ufixnum n-codepoints))

  (let ((word 0)
        (word-bits 0)
        (word-bits-left 0)
        (next 0)
        (next-bits 0)
        (result
         #?+hlmem/character=utf-16 (make-array  n-codepoints :element-type 'character
                                               :adjustable t :fill-pointer 0)
         #?-hlmem/character=utf-16 (make-string n-codepoints :element-type 'character)))

    (declare (type mem-word word next)
             (type (integer 0 #.+mem-word/bits+) word-bits word-bits-left next-bits))

    (dotimes (i n-codepoints)
      (declare (ignorable i))
      
      (loop while (< word-bits 32) ;; UTF-8 needs at most 32 bits to encode a character
         do
           (when (and (zerop next-bits)
                      (< index end-index))
             (setf next (mget-word ptr index)
                   next-bits +mem-word/bits+)
             (incf-mem-size index))

           (setf word-bits-left (- +mem-word/bits+ word-bits)
                 word      (logior word (logand +mem-word/mask+ (ash next word-bits)))
                 word-bits (min +mem-word/bits+ (+ next-bits word-bits))
                 next      (ash next (- word-bits-left))
                 next-bits (max 0 (- next-bits word-bits-left)))

           (unless (< index end-index)
             (return)))

      (multiple-value-bind (code bits) (%utf-8-word->codepoint word)

        #?+hlmem/character=utf-16
        (multiple-value-bind (ch1 ch2) (%codepoint->utf-16 code)
          (vector-push-extend ch1 result)
          (when ch2
            (vector-push-extend ch2 result)))

        #?-hlmem/character=utf-16
        (setf (schar result i) (%codepoint->character code))
        
        (setf word      (ash word (- bits))
              word-bits (max 0 (- word-bits bits)))))
    
    (when (>= (+ word-bits next-bits) +mem-word/bits+)
      ;; problem... we read one word too much
      (decf-mem-size index))

    (values result index)))
  

(defun mread-box/string-utf-8 (ptr index end-index)
  "Read a string from the memory starting at (PTR+INDEX) and return it.
Also return as additional value INDEX pointing to immediately after words read.

Assumes BOX header was already read."
  (declare (type maddress ptr)
           (type mem-size index end-index))
  
  (let* ((n-codepoints (mget-uint ptr index))
         (min-n-words (mem-size+1 (ceiling n-codepoints +msizeof-word+))))
    
    (check-array-length ptr index 'string n-codepoints)
    (check-mem-length ptr index end-index min-n-words)

    (%mread-string-utf-8 ptr (mem-size+1 index) end-index n-codepoints)))
