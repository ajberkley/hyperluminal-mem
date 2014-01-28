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
;;;;    boxed pathname                                                       ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun box-words/pathname (path)
  "Return the number of words needed to store pathname PATH in mmap memory,
not including BOX header."
  (declare (type pathname path))

  (let* ((host (pathname-host path :case :common))
         (default-host (pathname-host *default-pathname-defaults* :case :common))

         (n-words (+ (detect-n-words (if (eq host default-host) nil host))
                     (detect-n-words (pathname-device path :case :common))
                     (detect-n-words (pathname-directory path :case :common))
                     (detect-n-words (pathname-name path :case :common))
                     (detect-n-words (pathname-type path :case :common))
                     (detect-n-words (pathname-version path)))))
    (unless (<= n-words +mem-box/max-payload-words+)
      (error "HYPERLUMINAL-DB: pathname too large for object store,
it requires ~S words, maximum supported is ~S words"
             (1+ n-words) +mem-box/max-words+))
    (the mem-size n-words)))



  

(defun mwrite-box/pathname (ptr index end-index path)
  "write pathname PATH into the memory starting at (PTR+INDEX).
Assumes BOX header is already written."
  (declare (type maddress ptr)
           (type mem-size index)
           (type pathname path))

  (let ((mwrite #'mwrite)
        (host (pathname-host path :case :common))
        (default-host (pathname-host *default-pathname-defaults* :case :common)))

    (setf index (funcall mwrite ptr index end-index (if (eq host default-host) nil host)))
    (setf index (funcall mwrite ptr index end-index (pathname-device path :case :common)))
    (setf index (funcall mwrite ptr index end-index (pathname-directory path :case :common)))
    (setf index (funcall mwrite ptr index end-index (pathname-name path :case :common)))
    (setf index (funcall mwrite ptr index end-index (pathname-type path :case :common)))
    (setf index (funcall mwrite ptr index end-index (pathname-version path)))
    index))


(defun mread-box/pathname (ptr index end-index)
  "Read a pathname from the memory starting at (PTR+INDEX) and return it.
Assumes BOX header was already read."
  (declare (type maddress ptr)
           (type mem-size index))
  
  (let ((mread #'mread))
    (multiple-value-bind (host index) (funcall mread ptr index end-index)
      (multiple-value-bind (device index) (funcall mread ptr index end-index)
        (multiple-value-bind (directory index) (funcall mread ptr index end-index)
          (multiple-value-bind (name index) (funcall mread ptr index end-index)
            (multiple-value-bind (type index) (funcall mread ptr index end-index)
              (multiple-value-bind (version index) (funcall mread ptr index end-index)
                (values
                 (make-pathname
                  :host (or host (pathname-host *default-pathname-defaults* :case :common))
                  :device device :directory directory
                  :name name :type type :version version :case :common)
                 index)))))))))
