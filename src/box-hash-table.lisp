;; -*- lisp -*-

;; This file is part of hyperluminal-DB.
;; Copyright (c) 2013 Massimiliano Ghilardi
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.


(in-package :hyperluminal-db)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;    boxed hash-table                                                       ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun box-words/hash-table (htable)
  "Return the number of words needed to store hash-table HTABLE in mmap memory,
not including BOX header."
  (declare (type hash-table htable))

  (let ((len (hash-table-count htable)))
    (unless (<= len +most-positive-int+)
      (error "HYPERLUMINAL-DB: hash-table too large for object store.
it contains ~S entries, maximum supported is ~S entries"
	     len +most-positive-int+)))

  ;; -1 to store number of entries
  (let ((words-left (1- +mem-box/max-payload-words+)))

    (declare (type mem-size words-left))
    ;; count downward: easier to check for overflows

    (let ((detect-n-words #'detect-n-words))
      (loop for k being the hash-keys in htable using (hash-value v)
         for k-len = (the mem-size (funcall detect-n-words k))
         for v-len = (the mem-size (funcall detect-n-words v))
         do
           (unless (and (>= words-left k-len)
                        (progn
                          (decf-mem-size words-left k-len)
                          (>= words-left v-len)))

             (error "HYPERLUMINAL-DB: hash-table too large for object store,
it requires more space than the maximum supported ~S words"
                    +mem-box/max-payload-words+))

           (decf-mem-size words-left v-len)))
           
    (mem-size- +mem-box/max-payload-words+ words-left)))

  

(defun mwrite-box/hash-table (ptr index htable)
  "Write hash-table HTABLE into the memory starting at (PTR+INDEX).
Return number of words actually written.

Assumes BOX header is already written, and that enough memory is available
at (PTR+INDEX)."
  (declare (type maddress ptr)
           (type mem-size index)
           (type hash-table htable))

  (let ((orig-index index)
	(mwrite #'mwrite)
        (len (hash-table-count htable))
        (test (hash-table-test htable)))

    (mset-int ptr index (if (or (eq test 'eq) (eq test 'equal))
                            len
                            (lognot len)))
                            
    (incf-mem-size index)

    (loop for k being the hash-keys in htable using (hash-value v)
       do
         (incf-mem-size index (funcall mwrite ptr index k))
         (incf-mem-size index (funcall mwrite ptr index v)))

    ;; return number of words actually written, including BOX header
    (mem-size+ +mem-box/header-words+
	       (mem-size- index orig-index))))


(define-constant-once +hash-table-tests+ #(eq eql equal equalp))

(defun mread-box/hash-table (ptr index)
  "Read a hash-table from the boxed memory starting at (PTR+INDEX) and return it.
Also returns number of words actually read as additional value.

Assumes BOX header was already read."
  (declare (type maddress ptr)
           (type mem-size index))
  
  (let* ((orig-index index)
         ;; re-read BOX header, because we need the boxed-type
         (boxed-type (mget-fulltag ptr (mem-size- index +mem-box/header-words+)))
         (test-index (if (= boxed-type +mem-box/hash-table-eq+) 0 2))
	 (len (mget-int ptr index)))

    (declare (type (mod 4) test-index)
             (type mem-int len))
         
    (when (< len 0)
      (incf test-index)
      (setf len (lognot len)))

    (incf-mem-size index)

    (let ((mread #'mread)
          (htable (make-hash-table :test (svref +hash-table-tests+ test-index)
                                   :size len)))
      (loop for i from 0 below len
	 do (multiple-value-bind (k k-len) (funcall mread ptr index)
	      (incf-mem-size index k-len)
              (multiple-value-bind (v v-len) (funcall mread ptr index)
                (incf-mem-size index v-len)
                (setf (gethash k htable) v))))

      (values
       htable
       (mem-size+ +mem-box/header-words+
                  (mem-size- index orig-index))))))
