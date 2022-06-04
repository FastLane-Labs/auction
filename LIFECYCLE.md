                                      until all are processed
                              ┌─────────────────────────┐
                              │                         │
┌──────────┐           ┌──────▼──────┐          ┌───────┴────────┐
│          │           │             │          │                │
│  STARTED ├──────────►│  PROCESSING ├─────────►│    PARTIAL     │
│          │           │             │          │    PROCESS     │
└──────────┘           └──────┬──────┘          └────────────────┘
                              │
                              │
                              │
                       ┌──────▼──────┐
                       │             │
                       │    ENDED    │
                       │             │
                       └─────────────┘


  Started: Can bid

  Processing: Bidding stopped

  Partial Process: Ongoing

  Ended: Can't bid, waiting for new