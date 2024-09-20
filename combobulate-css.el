;;; combobulate-css.el --- css mode support for combobulate  -*- lexical-binding: t; -*-

;; Copyright (C) 2021-23  Mickey Petersen

;; Author: Mickey Petersen <mickey at masteringemacs.org>
;; Package-Requires: ((emacs "29"))
;; Version: 0.1
;; Homepage: https://www.github.com/mickeynp/combobulate
;; Keywords: convenience, tools, languages

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

;; For `css-ts-mode'

;;; Code:

(require 'combobulate-settings)
(require 'combobulate-navigation)
(require 'combobulate-rules)
(require 'combobulate-setup)
(require 'subr-x)

(defun combobulate-css-pretty-print-node-name (node default-name)
  "Pretty printer for JS and JSX nodes"
  (pcase (combobulate-node-type node)
    ("declaration" (thread-first node
                                 (combobulate-node-child 0)
                                 (combobulate-node-text)))
    ("rule_set" (thread-first node
                              (combobulate-node-child 0)
                              (combobulate-node-text)))
    ("property_name" (thread-first node
                                   (combobulate-node-parent)
                                   (combobulate-node-child 1)
                                   (combobulate-node-text)))
    (_ default-name)))

(eval-and-compile
  (defvar combobulate-css-definitions
    '((envelope-procedure-shorthand-alist
       '((wrap-expressions . ((:activation-nodes ((:nodes ((rule "arguments")))))))))
      (envelope-list
       '((:description
          "Envelop in a media query"
          :key "@m"
          :mark-node t
          :nodes ("rule_set")
          :name "media-query"
          :template ("@media "
                     (choice* :rest ("(min-width: " (p 768px "min-width") @ ") {"))
                     (choice* :rest ("(max-width: " (p 768px "max-width") @ ") {")) >
                     (choice* :rest ("(max-height: " (p 1024px "max-height") @ ") {"))
                     (choice* :rest ("(min-height: " (p 1024px "min-height") @ ") {"))
                     (choice* :rest ("(orientation: " (choice "portrait") (choice "landscape") @ ") {"))
                     (choice* :rest ("(aspect-ratio: " (choice "16/9") (choice "4/3") @ ") {"))
                     n> r> >
                     n > "}" >))))
      (context-nodes
       '("class_name" "property_name" "feature_name" "float_name" "integer_value"
         "id_name" "plain_value" "color_value" "string_value"))
      (pretty-print-node-name-function
       #'combobulate-css-pretty-print-node-name)
      (procedures-edit nil)
      (procedures-sexp
       '((:activation-nodes ((:nodes ("comment" "property_name"
                                      (rule "selectors")
                                      (rule "arguments")))))))
      (procedures-hierarchy
       '((:activation-nodes ((:nodes ("block") :position at)) :selector (:choose node :match-children (:match-rules (rule "block"))))
         (:activation-nodes ((:nodes ("media_statement") :position at)) :selector (:choose node :match-children (:match-rules "block")))
         (:activation-nodes ((:nodes (all))) :selector (:choose node :match-children t))))
      (procedures-sibling
       '(;; declarations' own property values should be siblings, but
         ;; not property_name as it's a child of declaration also,
         ;; and that'd mean the LHS and RHS are siblings of another,
         ;; which would be weird.
         (:activation-nodes
          ((:nodes
            ((rule "feature_query")
             (rule "arguments"))
            :has-parent ("feature_query" "arguments")))
          :selector (:choose parent
                             :match-children t))
         (:activation-nodes
          ((:nodes
            ((exclude (rule "declaration") "property_name"))
            :has-parent ("declaration")))
          :selector (:choose parent
                             :match-children (:discard-rules ("comment" "property_name"))))
         (:activation-nodes
          ((:nodes
            ((rule "block")
             (rule "stylesheet"))
            :has-parent ("stylesheet" "block")))
          :selector (:match-children (:discard-rules ("comment"))))
         ;; declarations are siblings in a block
         (:activation-nodes
          ((:nodes
            ("declaration")
            :has-parent ("block")))
          :selector (:match-children (:discard-rules ("comment" "property_name"))))))
      (procedures-defun
       '((:activation-nodes ((:nodes (exclude (all) "declaration")))))))))


(define-combobulate-language
 :name css
 :language css
 :major-modes (css-mode css-ts-mode)
 :custom combobulate-css-definitions
 :setup-fn combobulate-css-setup)

(defun combobulate-css-setup (_))


(provide 'combobulate-css)
;;; combobulate-css.el ends here
