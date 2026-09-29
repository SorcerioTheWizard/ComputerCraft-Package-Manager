# Roadmap: todo

> Generated with `docket docs roadmap`.

```mermaid
graph TD
  subgraph FEAT
    FEAT_1["FEAT-1<br/>Publish an Official CCPM<br/>Datapack<br/>p2 todo"]
    FEAT_2["FEAT-2<br/>Add a Ccpm Distribute<br/>Command for Floppy Disks<br/>p2 todo"]
  end
  subgraph SOC
    SOC_1["SOC-1<br/>Add CCPM to<br/>Awesome-cctweaked<br/>p2 todo"]
    SOC_2["SOC-2<br/>Record a Demo Video<br/>p2 todo"]
    SOC_3["SOC-3<br/>Announce CCPM on<br/>r/ComputerCraft<br/>p2 todo"]
    SOC_4["SOC-4<br/>Announce CCPM on the CC:<br/>Tweaked Discord<br/>p2 todo"]
    SOC_5["SOC-5<br/>Register CCPM on<br/>Pinestore<br/>p2 todo"]
  end
  SOC_2 --> SOC_3
  SOC_2 --> SOC_4
  SOC_5 --> SOC_3
  SOC_5 --> SOC_4
  classDef todoP2 fill:#495057,color:#fff,stroke:#ffd43b,stroke-width:2px
  class FEAT_1,FEAT_2,SOC_1,SOC_2,SOC_3,SOC_4,SOC_5 todoP2
```

## Legend

| Shape | Status |
|---|---|
| `[ ]` | todo, not started |
| `{ }` | wip, in flight |
| `( )` | done |

Arrows indicate required order of operations.

Each node's border represents its priority. Heaviest is higher priority.
