//! Per-app daily statistics (`byApp`), backward-compatible legacy JSON decoding,
//! soft muted pastel `AppPalette`, and `StackedBucket` builder for the Insights histogram.

use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const OTHER_APP: &str = "_other";
pub const OTHERS_GROUP: &str = "_others";
pub const MAX_PALETTE_APPS: usize = 6;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Day {
    #[serde(default)]
    pub words: u64,
    #[serde(default)]
    pub completions: u64,
    /// Words accepted per application ID on that day. Empty in pre-0.9.0 files (`#[serde(default)]`).
    #[serde(default, rename = "byApp")]
    pub by_app: BTreeMap<String, u64>,
}

impl Day {
    pub fn app_breakdown(&self) -> BTreeMap<String, u64> {
        let mut out = self.by_app.clone();
        let attributed: u64 = self.by_app.values().sum();
        if self.words > attributed {
            *out.entry(OTHER_APP.to_string()).or_insert(0) += self.words - attributed;
        }
        out
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Stats {
    #[serde(default)]
    pub days: BTreeMap<String, Day>,
    #[serde(default, rename = "perApp")]
    pub per_app: BTreeMap<String, u64>,
}

impl Stats {
    pub fn record(&mut self, date: NaiveDate, app: &str, words: u64) {
        let key = date.format("%Y-%m-%d").to_string();
        let day = self.days.entry(key).or_default();
        day.words += words;
        day.completions += 1;
        if !app.is_empty() {
            *day.by_app.entry(app.to_string()).or_insert(0) += words;
            *self.per_app.entry(app.to_string()).or_insert(0) += words;
        }
    }

    pub fn streak(&self, today: NaiveDate) -> u32 {
        let fmt = |d: NaiveDate| d.format("%Y-%m-%d").to_string();
        let mut cursor = today;
        if self.days.get(&fmt(cursor)).map(|d| d.words).unwrap_or(0) == 0 {
            let Some(yesterday) = cursor.pred_opt() else { return 0 };
            cursor = yesterday;
        }
        let mut count = 0u32;
        while self.days.get(&fmt(cursor)).map(|d| d.words).unwrap_or(0) > 0 {
            count += 1;
            let Some(prev) = cursor.pred_opt() else { break };
            cursor = prev;
        }
        count
    }

    pub fn app_totals<'a>(days: impl IntoIterator<Item = &'a Day>) -> Vec<(String, u64)> {
        let mut sum: BTreeMap<String, u64> = BTreeMap::new();
        for d in days {
            for (k, v) in d.app_breakdown() {
                if v > 0 {
                    *sum.entry(k).or_insert(0) += v;
                }
            }
        }
        let mut vec: Vec<(String, u64)> = sum.into_iter().collect();
        vec.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        vec
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct PastelPair {
    pub light_hex: &'static str,
    pub dark_hex: &'static str,
}

/// Soft muted pastel palette matching the macOS `AppPalette`.
pub const PASTEL_TONES: [PastelPair; 6] = [
    PastelPair { light_hex: "#B8B5F4", dark_hex: "#8E8AD6" }, // Soft Lavender
    PastelPair { light_hex: "#A8E0CE", dark_hex: "#6FB8A2" }, // Soft Mint
    PastelPair { light_hex: "#A7D2F4", dark_hex: "#6FA6D4" }, // Powder Sky
    PastelPair { light_hex: "#F6C6B5", dark_hex: "#D49580" }, // Peach Blush
    PastelPair { light_hex: "#F2DFA8", dark_hex: "#C9B273" }, // Buttercup Mist
    PastelPair { light_hex: "#EFC0D4", dark_hex: "#C48BA4" }, // Rose Quartz
];

pub const PASTEL_NEUTRAL: PastelPair = PastelPair {
    light_hex: "#CBD4E1",
    dark_hex: "#7D8899",
};

#[derive(Debug, Clone)]
pub struct AppPalette {
    pub ranked: Vec<String>,
}

impl AppPalette {
    pub fn new(ranked_apps: impl IntoIterator<Item = String>) -> Self {
        let ranked = ranked_apps
            .into_iter()
            .filter(|a| a != OTHER_APP)
            .take(MAX_PALETTE_APPS)
            .collect();
        Self { ranked }
    }

    pub fn group(&self, app: &str) -> String {
        if self.ranked.iter().any(|r| r == app) {
            app.to_string()
        } else {
            OTHERS_GROUP.to_string()
        }
    }

    pub fn color(&self, app: &str) -> PastelPair {
        self.ranked
            .iter()
            .position(|r| r == app)
            .map(|idx| PASTEL_TONES[idx % PASTEL_TONES.len()])
            .unwrap_or(PASTEL_NEUTRAL)
    }

    pub fn order(&self) -> Vec<String> {
        let mut out = self.ranked.clone();
        out.push(OTHERS_GROUP.to_string());
        out
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Grouping {
    Day,
    Week,
    Month,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BucketSegment {
    pub app: String,
    pub words: u64,
    pub light_hex: &'static str,
    pub dark_hex: &'static str,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StackedBucket {
    pub period_start: String,
    pub segments: Vec<BucketSegment>,
}

impl StackedBucket {
    pub fn total(&self) -> u64 {
        self.segments.iter().map(|s| s.words).sum()
    }

    pub fn make(days: &[(NaiveDate, Day)], grouping: Grouping, palette: &AppPalette) -> Vec<Self> {
        let mut starts: Vec<NaiveDate> = Vec::new();
        let mut sums: BTreeMap<NaiveDate, BTreeMap<String, u64>> = BTreeMap::new();

        for (date, day) in days {
            let bucket_start = match grouping {
                Grouping::Day => *date,
                Grouping::Week => {
                    let offset = date.weekday().num_days_from_monday() as i64;
                    *date - chrono::Duration::days(offset)
                }
                Grouping::Month => NaiveDate::from_ymd_opt(date.year(), date.month(), 1).unwrap_or(*date),
            };
            if !sums.contains_key(&bucket_start) {
                starts.push(bucket_start);
                sums.insert(bucket_start, BTreeMap::new());
            }
            let entry = sums.get_mut(&bucket_start).unwrap();
            for (app, w) in day.app_breakdown() {
                if w > 0 {
                    *entry.entry(palette.group(&app)).or_insert(0) += w;
                }
            }
        }

        let order = palette.order();
        starts
            .into_iter()
            .map(|start| {
                let map = sums.remove(&start).unwrap_or_default();
                let segments = order
                    .iter()
                    .filter_map(|k| {
                        let w = *map.get(k)?;
                        if w == 0 {
                            return None;
                        }
                        let pair = palette.color(k);
                        Some(BucketSegment {
                            app: k.clone(),
                            words: w,
                            light_hex: pair.light_hex,
                            dark_hex: pair.dark_hex,
                        })
                    })
                    .collect();
                StackedBucket {
                    period_start: start.format("%Y-%m-%d").to_string(),
                    segments,
                }
            })
            .collect()
    }
}

/// Four round grid steps of 1, 2 or 5 × 10ⁿ above `v`.
pub fn nice_ceiling(v: u64) -> u64 {
    if v <= 4 {
        return 4;
    }
    let need = v as f64 / 4.0;
    let mut p = 1u64;
    loop {
        for m in [1u64, 2, 5] {
            if (m * p) as f64 >= need {
                return m * p * 4;
            }
        }
        p *= 10;
    }
}
