(defvar tush-command "tush-run")

(defun tush ()
  "Run the current buffer through tush-run."
  (interactive)
  (let ((rc (call-process-region (point-min) (point-max) tush-command t t)))
    (cond ((zerop rc)                        ;success
           (message "tushed"))
          ((numberp rc)
           (message "tush-run process failed"))
          (t (message rc)))))

(global-set-key "\M-i" 'tush)
