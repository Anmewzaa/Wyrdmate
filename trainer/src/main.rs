//! Trains a (768 -> HIDDEN)x2 -> 1 NNUE with bullet.
//!
//! Usage: wyrdmate-trainer <data.data> [superbatches=20] [batches_per_superbatch=1000] [batch_size=16384] [wdl=0.5] [net_id=wyrd]
//! Convert datagen text first:
//!   bullet-utils convert --from text --input data/selfplay.txt --output data/selfplay.data
//! Nets land in checkpoints/<net_id>-<superbatch>/ (git-ignored).

use bullet_lib::{
    game::inputs::Chess768,
    nn::optimiser::AdamW,
    trainer::{
        save::SavedFormat,
        schedule::{lr, wdl, TrainingSchedule, TrainingSteps},
        settings::LocalSettings,
    },
    value::{loader, ValueTrainerBuilder},
};

const HIDDEN_SIZE: usize = 32;
const SCALE: i32 = 400;
const QA: i16 = 255;
const QB: i16 = 64;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let data = a.get(1).expect("usage: wyrdmate-trainer <data.data> [superbatches] [batches_per_sb] [batch_size]");
    let superbatches: usize = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(20);
    let batches_per_sb: usize = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(1000);
    let batch_size: usize = a.get(4).and_then(|s| s.parse().ok()).unwrap_or(16_384);
    let wdl: f32 = a.get(5).and_then(|s| s.parse().ok()).unwrap_or(0.5);
    let net_id = a.get(6).cloned().unwrap_or_else(|| "wyrd".to_string());

    let mut trainer = ValueTrainerBuilder::default()
        .dual_perspective()
        .optimiser(AdamW)
        .inputs(Chess768)
        .save_format(&[
            SavedFormat::id("l0w").round().quantise::<i16>(QA),
            SavedFormat::id("l0b").round().quantise::<i16>(QA),
            SavedFormat::id("l1w").round().quantise::<i16>(QB),
            SavedFormat::id("l1b").round().quantise::<i16>(QA * QB),
        ])
        .loss_fn(|output, target| output.sigmoid().squared_error(target))
        .build(|builder, stm_inputs, ntm_inputs| {
            let l0 = builder.new_affine("l0", 768, HIDDEN_SIZE);
            let l1 = builder.new_affine("l1", 2 * HIDDEN_SIZE, 1);
            let stm_hidden = l0.forward(stm_inputs).screlu();
            let ntm_hidden = l0.forward(ntm_inputs).screlu();
            l1.forward(stm_hidden.concat(ntm_hidden))
        });

    let schedule = TrainingSchedule {
        net_id,
        eval_scale: SCALE as f32,
        steps: TrainingSteps {
            batch_size,
            batches_per_superbatch: batches_per_sb,
            start_superbatch: 1,
            end_superbatch: superbatches,
        },
        wdl_scheduler: wdl::ConstantWDL { value: wdl },
        lr_scheduler: lr::StepLR { start: 0.001, gamma: 0.1, step: (superbatches * 3 / 4).max(1) },
        save_rate: (superbatches / 4).max(1),
    };

    let settings = LocalSettings { threads: 4, test_set: None, output_directory: "checkpoints", batch_queue_size: 64 };
    let loader = loader::DirectSequentialDataLoader::new(&[data.as_str()]);

    trainer.run(&schedule, &settings, &loader);
}
