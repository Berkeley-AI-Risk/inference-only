(in-package "ACL2")
(include-book "../first-value-numeric/ssv-spec" :uncertified-okp nil)
(include-book "../first-value-numeric/ssv-image" :uncertified-okp nil)

(defun first-v-profiles-through (limit image)
  (if (zp limit)
      t
    (and (ssv-profile-ok (1- limit) image)
         (first-v-profiles-through (1- limit) image))))

(defthm first-v-profile-at-member
  (implies (and (natp token) (natp limit) (< token limit)
                (first-v-profiles-through limit image))
           (ssv-profile-ok token image))
  :hints (("Goal" :induct (first-v-profiles-through limit image)
                  :in-theory (e/d (first-v-profiles-through)
                                  (ssv-profile-ok))))
  :rule-classes nil)

(defthm first-v-profile-check-complete-for-pinned-image
  (first-v-profiles-through 4019 (ssv-image))
  :hints (("Goal" :in-theory '((:e first-v-profiles-through) (:e ssv-image))))
  :rule-classes nil)

(defthm every-vocabulary-token-meets-first-v-numeric-profile
  (implies (and (natp token) (< token 4019))
           (ssv-profile-ok token (ssv-image)))
  :hints (("Goal"
           :use ((:instance first-v-profile-at-member (limit 4019) (image (ssv-image)))
                 first-v-profile-check-complete-for-pinned-image)
           :in-theory '((:e natp))))
  :rule-classes nil)
