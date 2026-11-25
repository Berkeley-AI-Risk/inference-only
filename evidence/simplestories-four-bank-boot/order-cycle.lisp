(in-package "SV")
(local (include-book "centaur/bitops/ihsext-basics" :dir :system))
(include-book "order-source-model")
(include-book "order-queue")

; An event carries the new levels of both clocks and independently sampled,
; binary interface inputs. Carry the previous levels across successive events.
(defun bo-wn (e) (loghead 1 (ifix e)))
(defun bo-rn (e) (loghead 1 (logtail 1 (ifix e))))
(defun bo-wv (e) (loghead 1 (logtail 2 (ifix e))))
(defun bo-ready (e) (loghead 1 (logtail 3 (ifix e))))
(defun bo-up (e) (loghead 1 (logtail 4 (ifix e))))
(defun bo-fail (e) (loghead 1 (logtail 5 (ifix e))))
(defun bo-word (e) (loghead 256 (logtail 6 (ifix e))))

; Observations: next FIFO, next loader, RAM strobe, loader-port handshake,
; loader-port data, FIFO-to-skid handshake. The waveform drives the two
; extracted RTL blocks using each other's actual pre-edge ports.
(defun bo-rtl-cycle (s a wp rp e)
  (let* ((f (bo-source-ports s))
         (app (bo-app-rtl-ports a (bo-up e) (bo-fail e) (bo-ready e) (nth 1 f) (nth 2 f)))
         (we (bo-source-rise-p wp (bo-wn e))) (re (bo-source-rise-p rp (bo-rn e))))
    (list (bo-source-edge s wp (bo-wn e) rp (bo-rn e) 1 1 (bo-wv e) (bo-word e) (nth 0 app))
          (bo-app-rtl-edge a rp (bo-rn e) 1 1 (bo-up e) (bo-fail e) (bo-ready e) (nth 1 f) (nth 2 f))
          (and we (equal (nth 0 f) 1) (equal (bo-wv e) 1))
          (and re (equal (nth 1 app) 1) (equal (bo-ready e) 1))
          (nth 2 app)
          (and re (equal (nth 4 app) 1)))))

(defun bo-model-cycle (s a wp rp e)
  (let* ((we (bo-source-rise-p wp (bo-wn e))) (re (bo-source-rise-p rp (bo-rn e)))
         (rr (bo-app-ready a (bo-up e) (bo-fail e))) (valid (if (equal (nth 9 s) 0) 1 0)))
    (list (bo-fifo-step s we re (bo-wv e) (bo-word e) rr)
          (bo-app-step a re (bo-up e) (bo-fail e) (bo-ready e) valid (nth 10 s))
          (bo-fifo-push-p s we (bo-wv e))
          (bo-app-take-p a re (bo-up e) (bo-fail e) (bo-ready e))
          (nth 1 a) (bo-fifo-pop-p s re rr))))

(local (defthm bo-input-bounds
  (and (unsigned-byte-p 1 (bo-wn e)) (unsigned-byte-p 1 (bo-rn e))
       (unsigned-byte-p 1 (bo-wv e)) (unsigned-byte-p 1 (bo-ready e))
       (unsigned-byte-p 1 (bo-up e)) (unsigned-byte-p 1 (bo-fail e))
       (unsigned-byte-p 256 (bo-word e)) (unsigned-byte-p 1 (bo-app-ready a up fail)))
  :hints (("Goal" :in-theory (disable loghead logtail unsigned-byte-p)))))
(local (defthm bo-data-width
  (implies (bo-fifo-state-p s) (unsigned-byte-p 256 (nth 10 s)))))

(local (in-theory (disable bo-wn bo-rn bo-wv bo-ready bo-up bo-fail bo-word bo-fifo-state-p
                           bo-app-state-p bo-source-edge bo-source-ports bo-app-rtl-edge bo-app-rtl-ports
                           bo-app-ready bo-app-valid bo-app-step bo-fifo-step unsigned-byte-p)))

(local (in-theory (enable (:executable-counterpart unsigned-byte-p))))

(local (defthm bo-cycle-fifo-ports
  (implies (bo-fifo-state-p s)
           (equal (bo-source-ports s)
                  (list (if (equal (nth 4 s) 0) 1 0) (if (equal (nth 9 s) 0) 1 0) (nth 10 s))))
  :hints (("Goal" :by bo-source-port-law))))

(local (defthm bo-cycle-fifo-transition
  (implies (and (bo-fifo-state-p s) (unsigned-byte-p 1 wp) (unsigned-byte-p 1 rp)
                (unsigned-byte-p 1 wn) (unsigned-byte-p 1 rn) (unsigned-byte-p 1 wv)
                (unsigned-byte-p 256 wd) (unsigned-byte-p 1 rr))
           (equal (bo-source-edge s wp wn rp rn 1 1 wv wd rr)
                  (bo-fifo-step s (bo-source-rise-p wp wn) (bo-source-rise-p rp rn) wv wd rr)))
  :hints (("Goal" :by bo-source-edge-is-step))))

(local (defthm bo-cycle-app-ports
  (implies (and (bo-app-state-p a) (unsigned-byte-p 1 up) (unsigned-byte-p 1 fail)
                (unsigned-byte-p 1 ready) (unsigned-byte-p 1 valid) (unsigned-byte-p 256 data))
           (equal (bo-app-rtl-ports a up fail ready valid data)
                  (list (bo-app-ready a up fail) (bo-app-valid a up fail) (nth 1 a)
                        (if (bo-app-take-p a t up fail ready) 1 0)
                        (if (and (equal valid 1) (equal (bo-app-ready a up fail) 1)) 1 0))))
  :hints (("Goal" :use ((:instance bo-app-source-laws (cp 0) (cn 0) (zp 1) (zn 1)))
           :in-theory (union-theories '((:executable-counterpart unsigned-byte-p)) (theory 'minimal-theory))))))

(local (defthm bo-cycle-app-transition
  (implies (and (bo-app-state-p a) (unsigned-byte-p 1 rp) (unsigned-byte-p 1 rn)
                (unsigned-byte-p 1 up) (unsigned-byte-p 1 fail) (unsigned-byte-p 1 ready)
                (unsigned-byte-p 1 valid) (unsigned-byte-p 256 data))
           (and (equal (bo-app-rtl-edge a rp rn 1 1 up fail ready valid data)
                       (bo-app-step a (bo-source-rise-p rp rn) up fail ready valid data))
                (bo-app-state-p (bo-app-step a (bo-source-rise-p rp rn) up fail ready valid data))))
  :hints (("Goal" :use ((:instance bo-app-source-laws (cp rp) (cn rn) (zp 1) (zn 1)))
           :in-theory (union-theories '(bo-source-rise-p (:executable-counterpart unsigned-byte-p)) (theory 'minimal-theory))))))

(defthm bo-rtl-cycle-refines-model
  (implies (and (bo-fifo-state-p s) (bo-app-state-p a)
                (unsigned-byte-p 1 wp) (unsigned-byte-p 1 rp))
           (equal (bo-rtl-cycle s a wp rp e) (bo-model-cycle s a wp rp e)))
  :hints (("Goal" :in-theory (disable bo-source-rise-p)))
  :rule-classes nil)

(defthm bo-model-app-preserves-width
  (implies (and (bo-fifo-state-p s) (bo-app-state-p a) (unsigned-byte-p 1 rp))
           (bo-app-state-p (nth 1 (bo-model-cycle s a wp rp e))))
  :hints (("Goal" :in-theory (disable bo-source-rise-p)))
  :rule-classes nil)
