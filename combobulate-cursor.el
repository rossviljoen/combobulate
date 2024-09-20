;;; combobulate-cursor.el --- third-party integrations for combobulate  -*- lexical-binding: t; -*-

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

;;

;;; Code:

(require 'combobulate-settings)
(require 'combobulate-navigation)
(require 'combobulate-setup)
(require 'combobulate-manipulation)
(require 'combobulate-envelope)
(require 'combobulate-query)

(defvar mc--default-cmds-to-run-once)


(declare-function mc/remove-fake-cursors "multiple-cursors-core.el")
(declare-function mc/maybe-multiple-cursors-mode "multiple-cursors-core.el")
(declare-function mc/create-fake-cursor-at-point "multiple-cursors-core.el")
(declare-function combobulate-tally-nodes "combobulate-manipulation.el")
(declare-function combobulate-procedure-collect-activation-nodes "combobulate-navigation")

(defvar multiple-cursors-mode)
(when (fboundp 'multiple-cursors-mode)
  (require 'multiple-cursors))

;; Generic wrappers for multiple cursors.
;;
;; TODO: Add support for other types of cursor editing (like iedit)

(defun combobulate--mc-assert-is-supported ()
  (unless (fboundp 'multiple-cursors-mode)
    (error "Multiple cursors is not installed or activated.")))

(defun combobulate--mc-active ()
  "Return non-nil if multiple cursors mode is active."
  (and (fboundp 'multiple-cursors-mode)
       multiple-cursors-mode))

(defun combobulate--mc-clear-cursors ()
  "Clear multiple cursors."
  (mc/remove-fake-cursors))

(defun combobulate--mc-enable ()
  "Enable multiple cursors."
  ;; abysmal MC hack to prevent MC from triggering on the damned
  ;; command that started the whole thing.
  (dolist (ignored-command '(combobulate-cursor-edit-sequence-dwim
                             combobulate-cursor-edit-node-type-dwim
                             combobulate-cursor-edit-node-siblings-dwim
                             combobulate-cursor-edit-node-by-text-dwim
                             combobulate-query-builder-edit-nodes
                             combobulate-cursor-edit-query))
    (add-to-list 'mc--default-cmds-to-run-once ignored-command))
  (mc/maybe-multiple-cursors-mode))

(defun combobulate--mc-place-cursor ()
  "Place a cursor at the current node."
  (mc/create-fake-cursor-at-point))

(defun combobulate--mc-place-nodes (placement-nodes &optional default-action)
  "Edit PLACEMENT-NODES according to each node's desired placement action.

Must be a list of cons cells where the car is the placement
action and the cdr is the node.

The car should be one of the following symbols:

`before', which puts the point at the node start; `after', which puts the
point at the node end; and `mark', which marks the node.

If DEFAULT-ACTION is non-nil, it is used for labelled nodes that do not have
match a placement action."
  (combobulate--mc-assert-is-supported)
  (if (combobulate--mc-active)
      ;; bail out if mc's running as we don't want to run mc
      ;; inside mc, which will happen if you trigger a command
      ;; from execute-extended-command for... some... reason..
      nil
    (let ((counter 0) (node-point) (do-mark) (matched)
          (default-action (or default-action 'before)))
      (cl-flet ((apply-action (action node)
                  (pcase action
                    ((or 'before '@before) (setq node-point (combobulate-node-start node)))
                    ((or 'after '@after) (setq node-point (combobulate-node-end node)))
                    ((or 'mark '@mark) (setq node-point (combobulate-node-start node)
                                             do-mark t))
                    (_ nil))))
        (combobulate--mc-clear-cursors)
        (pcase-dolist (`(,action . ,node) (reverse placement-nodes))
          (setq do-mark nil)
          (unless (apply-action action node)
            ;; fall back to `default-action' if we get nil back from
            ;; `apply-action'.
            (apply-action default-action node))
          (push (cons action node) matched)
          (if (= counter (- (length placement-nodes) 1))
              (progn (goto-char node-point)
                     (when do-mark (set-mark (combobulate-node-end node))))
            (goto-char node-point)
            (when do-mark (set-mark (combobulate-node-end node)))
            (combobulate--mc-place-cursor))
          (cl-incf counter))
        (combobulate--mc-enable)
        matched))))


(defvar combobulate-cursor--refactor-id nil
  "The ID of the current refactoring operation in progress.")

(defconst combobulate-cursor-substitute-default "\\0"
  "Substitute that represents the text for each individual node.

This is only used when Combobulate's editing mode is `combobulate'.")

(defconst combobulate-cursor-substitute-match (rx (group "\\" (group (1+ (any "0-9")))))
  "Regexp that matches the backslash and number in a regexp group.

Altering this is possible, but not recommended as other parts of the
code base make assumptions based on this.")

(defun combobulate-cursor--update-function (buf tag)
  "Return a function that updates the overlays in BUF with TAG.

This function is intended to be used in `post-command-hook' to
update the overlays in BUF with TAG. It is returned as a closure
that captures the minibuffer text at the time of its creation.

Overlays must be valid `combobulate-refactor' field overlays."
  (lambda ()
    (let ((idx 0)
          ;; nab the minibuffer text here (before we change the
          ;; current buffer) as we return a closure that runs in
          ;; `post-command-hook' inside the minibuffer prompt
          ;; machinery, and the minibuffer contents function will,
          ;; despite its name, happily return the contents of
          ;; *whatever* buffer is the current buffer, whether it is
          ;; actually a minibuffer or not.
          (minibuffer-text (minibuffer-contents)))
      (with-current-buffer buf
        (let ((ovs (combobulate--refactor-get-overlays combobulate-cursor--refactor-id)))
          (mapc (lambda (ov)
                  (when (overlay-get ov 'combobulate-refactor-field-enabled)
                    ;; Essential. There's a million things in here
                    ;; that throw errors left and right that'll cause
                    ;; `post-command-hook' to eject us from future
                    ;; updates if it gets a signal.
                    (ignore-errors
                      (combobulate--refactor-update-field
                       ov tag
                       (let* ((to (query-replace-compile-replacement minibuffer-text t))
                              ;; `replace-eval-replacement' and
                              ;; `query-replace-compile-replacement'
                              ;; rewrites `\,(...)'  elisp forms and
                              ;; detects regexp backslash groups such
                              ;; as `\N' and rewrites them as
                              ;; `(match-string N)' ---
                              ;; great. However, we cannot use this
                              ;; feature as it assumes match data is
                              ;; set (as it ordinarily would be in a
                              ;; normal search&replace loop) and the
                              ;; coterie of functions that depend on
                              ;; it.
                              ;;
                              ;; As we're effectively hacking up the
                              ;; replace machinery to work with
                              ;; Combobulate's refactoring system, we
                              ;; either need to rewrite uses of
                              ;; `match-string' to a custom function
                              ;; of our own choosing; ensure match
                              ;; data is set so it matches the field
                              ;; overlays in the buffer, which is
                              ;; complex; or just `cl-letf' it here
                              ;; temporarily.
                              (replacement-text
                               (cl-letf  (((symbol-function 'match-string)
                                           (lambda (n &optional _string)
                                             ;; Subtract 1 because 0
                                             ;; refers to the whole
                                             ;; match
                                             (overlay-get
                                              (nth (1- n) ovs)
                                              'combobulate-refactor-field-original-text))))
                                 (or (replace-eval-replacement
                                      (cond
                                       ((null to) "")
                                       ((stringp to)
		                        (list 'concat to))
		                       (t (cdr to)))
                                      idx)
                                     ""))))
                         (replace-regexp-in-string
                          combobulate-cursor-substitute-match
                          (lambda (sub)
                            ;; Avoid using any sort of matching
                            ;; functions here that touches match
                            ;; data. It does not work well due to
                            ;; `replace-regexp-in-string' doing its own
                            ;; thing with the data.
                            ;;
                            ;; Thankfully,
                            ;; `combobulate-cursor-substitute-match'
                            ;; is set to match backslash groups and
                            ;; they are syntactically simple: the
                            ;; first character is a backslash and the
                            ;; rest is a number. Extracting the number
                            ;; is as simple as the substring without
                            ;; the backslash.
                            (if-let (matched-ov
                                     (let ((num (string-to-number (substring sub 1))))
                                       ;; The number 0 is special. In
                                       ;; an ordinary search&replace
                                       ;; loop it refers to the whole
                                       ;; match. Here we repurpose it
                                       ;; to mean the original text of
                                       ;; the CURRENT field.  Also,
                                       ;; subtract 1 to account for
                                       ;; the 0-based whole match
                                       ;; index.
                                       (if (= num 0) (nth idx ovs) (nth (1- num) ovs))))
                                (overlay-get matched-ov 'combobulate-refactor-field-original-text)
                              ;; No match, return the default text in the minibuffer.
                              minibuffer-text))
                          replacement-text))
                       ;; required, as we need to ensure `default-text' is
                       ;; set to a default value that won't cause issues
                       ;; down the road if the eval replacement call does
                       ;; not yield anything.
                       ""))
                    (cl-incf idx)))
                ovs))))))

(defvar combobulate-cursor--field-tag 'combobulate-cursor-field
  "Tag used to identify Combobulate cursor fields.")



(defvar combobulate-cursor--active-buffer nil
  "The buffer that is currently being refactored.")

(defun combobulate-cursor-goto-field (direction)
  "Move to the next or previous field in DIRECTION."
  (with-current-buffer combobulate-cursor--active-buffer
    (let* ((ovs (combobulate--refactor-get-overlays combobulate-cursor--refactor-id))
           (wnd (get-buffer-window combobulate-cursor--active-buffer))
           (window-point (window-point wnd)))
      (if-let (ov (if (eq direction 'next)
                      (seq-find (lambda (ov) (> (overlay-start ov) window-point)) ovs)
                    (seq-find (lambda (ov) (< (overlay-start ov) window-point)) (reverse ovs))))
          (set-window-point wnd (overlay-start ov))
        (user-error "No more fields in this direction.")))))

(defun combobulate-cursor-next-field ()
  "Move to the next field in the cursor editing prompt."
  (interactive)
  (combobulate-cursor-goto-field 'next))

(defun combobulate-cursor-prev-field ()
  "Move to the previous field in the cursor editing prompt."
  (interactive)
  (combobulate-cursor-goto-field 'prev))

(defun combobulate-cursor-toggle-field (&optional pt)
  "Enable or disable the current field in the cursor editing prompt."
  ;; NOTE: do not use a letter here to capture the point as it must be
  ;; in the context of the window's point and not the minibuffer where
  ;; this is typically called from!
  (interactive)
  (with-current-buffer combobulate-cursor--active-buffer
    (combobulate-refactor (:id combobulate-cursor--refactor-id)
      (toggle-field (or pt (window-point (get-buffer-window combobulate-cursor--active-buffer)))
                    combobulate-cursor--field-tag))))

(defun combobulate-cursor-invert-fields ()
  "Invert the enabled/disabled state of all fields in the cursor editing prompt."
  (interactive)
  (with-current-buffer combobulate-cursor--active-buffer
    (combobulate-refactor (:id combobulate-cursor--refactor-id)
      (let ((ovs (combobulate--refactor-get-overlays combobulate-cursor--refactor-id)))
        (dolist (ov ovs)
          (combobulate-cursor-toggle-field (overlay-start ov)))))))

(defun combobulate-cursor-help ()
  (interactive)
  (with-electric-help
   (lambda ()
     (insert (substitute-command-keys "Combobulate Cursor Editing Help:

The default prompt value maps to the original text of each node,
represented by `\\0'.

You can use the value from a particular field by using the backslash
followed by the field number. For example, `\\1' refers to the first
field, `\\2' refers to the second field, and so on.

Like Emacs's normal replace commands, you can use the `\\#' shorthand to
insert a number equal to the index of the field, starting from the count
of 0.

You can also evaluate Emacs lisp forms in the context of each field with
the `\,(...)` syntax. For example, `\\,(upcase \\0)' will convert each
field to uppercase.

Cursor Key Bindings:

\\`C-n' - Move to the next field.
\\`C-p' - Move to the previous field.
\\`C-v' - Toggle the current field on or off.
\\`C-i' - Invert the enabled/disabled state of all fields.

General Key Bindings:

\\`C-h' - Show this help message.
\\`RET' - Accept the current prompt.
\\`C-g' - Abort the cursor editing.")))))

(defvar-keymap combobulate-cursor-key-map
  :parent combobulate-envelope-prompt-map
  :doc "Keymap for Combobulate's cursor editing prompt."
  "C-n" #'combobulate-cursor-next-field
  "C-p" #'combobulate-cursor-prev-field
  "C-v" #'combobulate-cursor-toggle-field
  "C-i" #'combobulate-cursor-invert-fields
  "C-h" #'combobulate-cursor-help)



(defun combobulate-cursor-edit-nodes (nodes &optional default-action ctx-node)
  "Interactively edit NODES optionally placed at DEFAULT-ACTION.

NODES is a list of nodes to edit, or a list of cons cells where the car
is the action to take and the cdr is the node to edit. Note that if
`combobulate-cursor-tool' is set to `combobulate', the action is
disregarded.

DEFAULT-ACTION is the action to take if NODES is a list of nodes. For
`multiple-cursors', the placement action (or DEFAULT-ACTION if the list
of NODES is not a list of cons cells) must be `before', `after', or
`mark'. For `combobulate', the value is disregarded.

CTX-NODE is the node that was used to generate NODES, such as a
parent node. It is only used for messaging."
  ;; Determine if we are dealing with a list of nodes or list of cons
  ;; cells.
  (let ((action-nodes
         (if (and (listp nodes)
                  (not (consp (car nodes))))
             (mapcar (lambda (node) (cons default-action node)) nodes)
           ;; action-nodes is a list of cons cells. So NODES must then
           ;; be turned into a flat list of nodes.
           (prog1 nodes
             (setq nodes (mapcar #'cdr nodes))))))
    (cond ((= (length nodes) 0)
           (combobulate-message "There are zero editable nodes."))
          (t (combobulate-message
              (concat "Editing " (combobulate-tally-nodes nodes t)
                      (and ctx-node (format " in `%s'"
                                            (propertize
                                             (combobulate-pretty-print-node ctx-node)
                                             'face 'combobulate-active-indicator-face)))))))
    (cond
     ((null nodes) (error "There are no editable nodes."))
     ((eq combobulate-cursor-tool 'combobulate)
      (let ((proxy-nodes (combobulate-proxy-node-make-from-nodes nodes))
            (combobulate-cursor--refactor-id (combobulate-refactor-setup))
            (combobulate-cursor--active-buffer (current-buffer)))
        (combobulate-refactor (:id combobulate-cursor--refactor-id)
          ;; Ditch the proxy nodes' text in the buffer and commit the
          ;; deletions immediately. The fields we insert will be the new
          ;; values.
          (mapc #'mark-node-deleted proxy-nodes)
          (commit)
          ;; Create new fields with the new values in the same places
          ;; as the old ones.
          (mapc (lambda (node)
                  (mark-field (combobulate-node-start node)
                              combobulate-cursor--field-tag
                              (combobulate-node-text node)))
                proxy-nodes)
          (combobulate-envelope-prompt
           (substitute-command-keys "Editing fields. Use \\`C-h' for help.")
           nil
           combobulate-cursor--active-buffer
           (combobulate-cursor--update-function
            combobulate-cursor--active-buffer
            combobulate-cursor--field-tag)
           combobulate-cursor-substitute-default
           combobulate-cursor-key-map)
          (commit))))
     ((eq combobulate-cursor-tool 'multiple-cursors)
      (combobulate--mc-place-nodes action-nodes))
     (t (error "Unknown cursor tool: %s" combobulate-cursor-tool)))))



(defun combobulate-cursor-edit-node-determine-action (arg)
  "Determine which action ARG should map to."
  (cond ((equal arg '(4)) 'after)
        ((equal arg '(16)) 'mark)
        (t 'before)))

(defun combobulate-cursor-edit-query ()
  "Edit clusters of nodes by query.

Uses the head of the ring `combobulate-query-ring' as the
query. If the ring is empty, then throw an error.

By default, point is placed at the start of each match. When
called with one prefix argument, place point at the end of the
matches. With two prefix arguments, mark the node instead."
  (interactive)
  (combobulate-query-ring--execute
   "Edit nodes matching this query?"
   "Placed cursors"
   (lambda (matches _query)
     (combobulate-cursor-edit-nodes matches))))

(defun combobulate-cursor-edit-node-siblings-dwim (arg)
  "Edit all siblings of the current node.

Combobulate will use its definition of siblings as per
\\[combobulate-navigate-next] and
\\[combobulate-navigate-previous]."
  (interactive "P")
  (with-navigation-nodes (:procedures (combobulate-read procedures-sibling))
    (let ((node (combobulate--get-nearest-navigable-node)))
      (combobulate-cursor-edit-nodes (combobulate-nav-get-siblings node)
                                     (combobulate-cursor-edit-node-determine-action arg)
                                     (or (car-safe (combobulate-nav-get-parents node t))
                                         node)))))

(defun combobulate-cursor-edit-sequence-dwim (arg)
  "Edit a sequence of nodes.

This looks for clusters of nodes to edit in
`procedures-sequence'.

If you specify a prefix ARG, then the points are placed at the
end of each edited node."
  (interactive "P")
  (with-navigation-nodes (:procedures (combobulate-read procedures-sequence))
    (if-let ((node (combobulate--get-nearest-navigable-node)))
        (combobulate-cursor-edit-sequence
         node
         (combobulate-cursor-edit-node-determine-action arg))
      (error "There is no sequence of nodes here"))))


(defun combobulate-cursor-edit-node-type-dwim (arg)
  "Edit nodes of the same type by node locus."
  (interactive "P")
  (with-navigation-nodes (:procedures (combobulate-read procedures-default))
    (if-let ((node (combobulate--get-nearest-navigable-node)))
        (combobulate-cursor-edit-identical-nodes
         node (combobulate-cursor-edit-node-determine-action arg)
         (lambda (tree-node) (and (equal (combobulate-node-type node)
                                    (combobulate-node-type tree-node))
                             (equal (combobulate-node-field-name node)
                                    (combobulate-node-field-name tree-node)))))
      (error "Cannot find any editable nodes here"))))

(defun combobulate-cursor-edit-node-by-text-dwim (arg)
  "Edit nodes with the same text by node locus.

This looks for nodes of of any type found in
`combobulate-navigable-nodes' that have the same text as
the node at point."
  (interactive "P")
  (if-let ((node (combobulate-node-at-point nil t)))
      (combobulate-cursor-edit-identical-nodes
       node (combobulate-cursor-edit-node-determine-action arg)
       (lambda (tree-node) (equal (combobulate-node-text tree-node)
                             (combobulate-node-text node))))
    (error "Cannot find any editable nodes here")))

(defun combobulate-cursor-edit-identical-nodes (node action &optional match-fn)
  "Edit nodes identical to NODE if they match MATCH-FN.

The locus of editable nodes is determined by NODE's parents and
is selectable.

MATCH-FN takes one argument, a node, and should return non-nil if it is
a match."
  (let ((matches)
        ;; default to 1 "match" as there's no point in creating
        ;; multiple cursors when there's just one match
        (ct 1)
        (grouped-matches))
    (dolist (start-node (combobulate-get-parents node))
      (let ((known-ranges (make-hash-table :test #'equal :size 1024)))
        (setq matches (flatten-tree (combobulate-induce-sparse-tree
                                     start-node
                                     (lambda (tree-node)
                                       (prog1
                                           (and (funcall match-fn tree-node)
                                                (not (gethash (combobulate-node-range tree-node) known-ranges nil)))
                                         (puthash (combobulate-node-range tree-node) t known-ranges)))))))
      ;; this catches parent nodes that do not add more, new, nodes to
      ;; the editing locus by filtering them out.
      (when (> (length matches) ct)
        (setq ct (length matches))
        (push (cons start-node matches) grouped-matches)))
    (combobulate-refactor ()
      (cl-flet ((current-matches (n) (cdr (assoc (combobulate-proxy-node-to-real-node n) grouped-matches))))
        (let* ((chosen-node (combobulate-proxy-node-to-real-node
                             (combobulate-proffer-choices
                              (reverse (mapcar 'car grouped-matches))
                              (lambda-slots (current-node proxy-nodes refactor-id)
                                (combobulate-refactor (:id refactor-id)
                                  (rollback)
                                  (mark-node-highlighted current-node)
                                  (princ (format "Editing %s in %s%s\n"
                                                 (combobulate-pretty-print-node-type current-node)
                                                 (combobulate-proxy-node-to-real-node current-node)
                                                 (and (combobulate-node-field-name current-node)
                                                      (format " (%s)"
                                                              (combobulate-node-field-name current-node)))))
                                  ;; rollback the outer
                                  ;; `combobulate-refactor' call so
                                  ;; the node cursors we place below
                                  ;; are properly erased.
                                  ;; place a fake cursor at every
                                  ;; node to indicate where the
                                  ;; matching nodes are.
                                  (mapc #'mark-node-cursor (current-matches current-node))
                                  ;; indicate the locus of editing
                                  ;; by highlighting the entire node
                                  ;; boundary.
                                  (mark-node-highlighted current-node)))
                              :flash-node t
                              :unique-only nil
                              :prompt-description
                              (lambda-slots (current-node proxy-nodes)
                                (concat
                                 (propertize
                                  (format "[%d/%d]" (length (current-matches current-node)) ct)
                                  'face 'shadow)
                                 " "
                                 (format "Edit `%s' in"

                                         (propertize (combobulate-pretty-print-node-type node)
                                                     'face 'combobulate-tree-branch-face)))))))
               (matches (cdr (assoc chosen-node grouped-matches))))
          (rollback)
          (combobulate-cursor-edit-nodes matches action chosen-node))))))

(defun combobulate-cursor-edit-sequence (node action)
  "Find the sequence, if there is one, NODE belongs to and ACTION them."
  (pcase-let (((cl-struct combobulate-procedure-result
                          (selected-nodes selected-nodes)
                          (parent-node parent-node))
               (or (car-safe (combobulate-procedure-start node))
                   (error "No sequence to edit."))))
    (combobulate-cursor-edit-nodes
     ;; Remove `@discard' matches.
     (mapcar 'cdr (seq-remove
                   ;; remove `@discard' matches. Tree-sitter does not
                   ;; return tags with `@', but Combobulate query
                   ;; search does.
                   (lambda (m) (or (equal (car m) '@discard)
                              (equal (car m) 'discard)))
                   selected-nodes))
     action
     parent-node)))

(provide 'combobulate-cursor)
;;; combobulate-cursor.el ends here
