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


;;;; * HYPERLUMINAL-DB

(in-package :cl-user)

(defpackage #:hyperluminal-db

  (:nicknames #:hldb)

  (:use #:cl #:hyperluminal-mem)

  (:import-from #:stmx.lang

                #:enable-#?-syntax  #:eval-always
                #:set-feature  #:set-features #:default-feature #:default-features
                #:get-feature  #:all-features?

                #:define-global                #:define-constant-once
                #:with-gensym  #:with-gensyms  #:new      #:let1
                #:when-bind    #:if-bind       #:awhen    #:aif 
                #:log.debug    #:log.trace     #:log.make-logger)

  (:import-from #:hyperluminal-mem

                #:+null-pointer+ #:+most-positive-size+
                #:+mem-box/min-words+    #:+mem-box/max-words+
                #:+mem-box/header-words+ #:+mem-box/min-payload-words+
                #:box-pointer->size #:size->box-pointer

                #:mem-size+ #:mem-size+1 #:mem-size- #:mem-size-1
                #:mget-value

                #:!mread #:!mwrite)

  (:export      #:hldb-version #:hldb-abi-version
                #:hldb-open    #:hldb-close))
                