(in-package :org-agent)
(defun consensus-propose-vote (proposal)
  "Broadcasts a proposal to the peer swarm and collects votes.
   Implements PSF Social Consensus Protocol."
  (let* ((peers (get-swarm-peer-list))
         (votes (loop for peer in peers 
                      collect (org-agent:send-swarm-packet peer `(:type :REQUEST :action :vote :proposal ,proposal)))))
    (if (> (count :YES votes) (/ (length peers) 2))
        t ; Consensus reached
        nil)))
