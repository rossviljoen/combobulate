;;; combobulate-julia.el --- Julia support for Combobulate  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Ross Viljoen

;; Author: Ross Viljoen <ross@viljoen.co.uk>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'combobulate-settings)
(require 'combobulate-navigation)
(require 'combobulate-manipulation)
(require 'combobulate-interface)
(require 'combobulate-rules)
(require 'combobulate-setup)

(defun combobulate-julia-pretty-print-node-name (node default-name)
  "Pretty print the node name for Julia mode."
  default-name)

(eval-and-compile
  (defvar combobulate-julia-definitions
    '((pretty-print-node-name-function #'combobulate-julia-pretty-print-node-name)
      (procedures-defun
       '((:activation-nodes ((:nodes ("function_definition" "short_function_definition" "function_expression" "struct_definition" "macro_definition"))))))
      (procedures-sexp
       '((:activation-nodes ((:nodes ("function_definition" "short_function_definition" "function_expression" "struct_definition" "macro_definition" "for_clause" "if_clause")))))))))

(define-combobulate-language
 :name julia
 :language julia
 :major-modes (julia-mode julia-ts-mode)
 :custom combobulate-julia-definitions
 :setup-fn combobulate-julia-setup)

(defun combobulate-julia-setup (_))

(provide 'combobulate-julia)
;;; combobulate-julia.el ends here
