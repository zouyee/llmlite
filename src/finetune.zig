//! Fine-tuning API

const std = @import("std");
const http = @import("http");

// ============================================================================
// Service
// ============================================================================

pub const Service = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) Service {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    pub fn deinit(self: *Service) void {
        _ = self;
    }

    /// Creates a fine-tuning job.
    pub fn createFineTuningJob(self: *Service, params: FineTuningJobParams) !FineTuningJob {
        const json_str = try self.serializeFineTuningJobParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/fine_tuning/jobs", json_str);
        defer self.allocator.free(response);

        return try self.parseFineTuningJob(response);
    }

    /// Lists fine-tuning jobs.
    pub fn listFineTuningJobs(self: *Service) !FineTuningJobList {
        const response = try self.http_client.get("/fine_tuning/jobs");
        defer self.allocator.free(response);
        return try self.parseFineTuningJobList(response);
    }

    /// Retrieves a fine-tuning job.
    pub fn getFineTuningJob(self: *Service, job_id: []const u8) !FineTuningJob {
        const path = try std.fmt.allocPrint(self.allocator, "/fine_tuning/jobs/{s}", .{job_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);
        return try self.parseFineTuningJob(response);
    }

    /// Cancels a fine-tuning job.
    pub fn cancelFineTuningJob(self: *Service, job_id: []const u8) !FineTuningJob {
        const path = try std.fmt.allocPrint(self.allocator, "/fine_tuning/jobs/{s}/cancel", .{job_id});
        defer self.allocator.free(path);

        const response = try self.http_client.post(path, "{}");
        defer self.allocator.free(response);
        return try self.parseFineTuningJob(response);
    }

    /// List events for a fine-tuning job.
    pub fn listFineTuningJobEvents(self: *Service, job_id: []const u8) !FineTuningJobEventList {
        const path = try std.fmt.allocPrint(self.allocator, "/fine_tuning/jobs/{s}/events", .{job_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);
        return try self.parseFineTuningJobEventList(response);
    }

    /// List checkpoints for a fine-tuning job.
    pub fn listFineTuningCheckpoints(self: *Service, job_id: []const u8) !FineTuningCheckpointList {
        const path = try std.fmt.allocPrint(self.allocator, "/fine_tuning/jobs/{s}/checkpoints", .{job_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);
        return try self.parseFineTuningCheckpointList(response);
    }

    fn serializeFineTuningJobParams(self: *Service, params: FineTuningJobParams) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        errdefer buf.deinit();

        try buf.append('{');
        try buf.appendSlice("\"training_file\":\"");
        try buf.appendSlice(params.training_file);
        try buf.append('"');

        if (params.model) |v| {
            try buf.appendSlice(",\"model\":\"");
            try buf.appendSlice(v);
            try buf.append('"');
        }

        if (params.validation_file) |v| {
            try buf.appendSlice(",\"validation_file\":\"");
            try buf.appendSlice(v);
            try buf.append('"');
        }

        if (params.suffix) |v| {
            try buf.appendSlice(",\"suffix\":\"");
            try buf.appendSlice(v);
            try buf.append('"');
        }

        if (params.seed) |v| {
            try buf.appendSlice(",\"seed\":");
            try buf.writer().print("{}", .{v});
        }

        if (params.hyperparameters) |hp| {
            try buf.appendSlice(",\"hyperparameters\":{");
            var first = true;
            if (hp.n_epochs) |v| {
                try buf.appendSlice("\"n_epochs\":");
                try buf.writer().print("{}", .{v});
                first = false;
            }
            if (hp.batch_size) |v| {
                if (!first) try buf.append(',');
                try buf.appendSlice("\"batch_size\":");
                try buf.writer().print("{}", .{v});
                first = false;
            }
            if (hp.learning_rate_multiplier) |v| {
                if (!first) try buf.append(',');
                try buf.appendSlice("\"learning_rate_multiplier\":");
                try buf.writer().print("{d}", .{v});
                first = false;
            }
            if (hp.prompt_loss_weight) |v| {
                if (!first) try buf.append(',');
                try buf.appendSlice("\"prompt_loss_weight\":");
                try buf.writer().print("{d}", .{v});
            }
            try buf.append('}');
        }

        try buf.append('}');
        return try buf.toOwnedSlice();
    }

    fn parseFineTuningJob(self: *Service, response: []const u8) !FineTuningJob {
        const id = self.parseJsonField(response, "id") orelse "unknown";
        const created_str = self.parseJsonField(response, "created_at") orelse "0";
        const model = self.parseJsonField(response, "model") orelse "unknown";
        const status = self.parseJsonField(response, "status") orelse "unknown";
        const training_file = self.parseJsonField(response, "training_file") orelse "unknown";

        const fine_tuned_model = self.parseJsonField(response, "fine_tuned_model");
        const organization_id = self.parseJsonField(response, "organization_id");

        // Parse hyperparameters
        const hp_str = self.parseJsonField(response, "hyperparameters");
        const hp = if (hp_str) |s| try self.parseHyperparameters(s) else Hyperparameters{};

        // Parse result_files
        const result_files_str = self.parseJsonField(response, "result_files");
        const result_files = if (result_files_str) |s|
            try self.parseStringArray(s)
        else
            &.{}[0..];

        const finished_at_str = self.parseJsonField(response, "finished_at");
        const finished_at: ?u64 = if (finished_at_str) |s|
            std.fmt.parseInt(u64, s, 10) catch null
        else
            null;

        const trained_tokens_str = self.parseJsonField(response, "trained_tokens");
        const trained_tokens: ?u64 = if (trained_tokens_str) |s|
            std.fmt.parseInt(u64, s, 10) catch null
        else
            null;

        const estimated_finish_str = self.parseJsonField(response, "estimated_finish");
        const estimated_finish: ?u64 = if (estimated_finish_str) |s|
            std.fmt.parseInt(u64, s, 10) catch null
        else
            null;

        // Parse job_error if present
        const job_error_str = self.parseJsonField(response, "job_error");
        const job_error: ?FineTuningJobError = if (job_error_str) |s|
            try self.parseFineTuningJobError(s)
        else
            null;

        return FineTuningJob{
            .id = try self.allocator.dupe(u8, id),
            .created_at = std.fmt.parseInt(u64, created_str, 10) catch 0,
            .model = try self.allocator.dupe(u8, model),
            .status = try self.allocator.dupe(u8, status),
            .training_file = try self.allocator.dupe(u8, training_file),
            .fine_tuned_model = if (fine_tuned_model) |v| try self.allocator.dupe(u8, v) else null,
            .organization_id = if (organization_id) |v| try self.allocator.dupe(u8, v) else null,
            .hyperparameters = hp,
            .result_files = result_files,
            .finished_at = finished_at,
            .trained_tokens = trained_tokens,
            .estimated_finish = estimated_finish,
            .job_error = job_error,
        };
    }

    fn parseFineTuningJobList(self: *Service, response: []const u8) !FineTuningJobList {
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        const data_str = self.parseJsonField(response, "data") orelse return error.ParseError;

        // Count jobs
        var count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, data_str, search_pos, "\"id\":")) |_| {
            count += 1;
            search_pos += 1;
        }

        var jobs = try self.allocator.alloc(FineTuningJob, count);
        errdefer self.allocator.free(jobs);

        var parsed: usize = 0;
        search_pos = 0;
        while (parsed < count) {
            const obj_start = std.mem.indexOfPos(u8, data_str, search_pos, "{") orelse break;
            var depth: u32 = 1;
            var i = obj_start + 1;
            while (i < data_str.len and depth > 0) {
                if (data_str[i] == '{') depth += 1;
                if (data_str[i] == '}') depth -= 1;
                i += 1;
            }
            const obj_str = data_str[obj_start..i];
            jobs[parsed] = try self.parseFineTuningJob(obj_str);
            parsed += 1;
            search_pos = i;
        }

        return FineTuningJobList{
            .data = jobs,
            .has_more = has_more,
        };
    }

    fn parseFineTuningJobEventList(self: *Service, response: []const u8) !FineTuningJobEventList {
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        const data_str = self.parseJsonField(response, "data") orelse return error.ParseError;

        // Count events
        var count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, data_str, search_pos, "\"id\":")) |_| {
            count += 1;
            search_pos += 1;
        }

        var events = try self.allocator.alloc(FineTuningJobEvent, count);
        errdefer self.allocator.free(events);

        var parsed: usize = 0;
        search_pos = 0;
        while (parsed < count) {
            const obj_start = std.mem.indexOfPos(u8, data_str, search_pos, "{") orelse break;
            var depth: u32 = 1;
            var i = obj_start + 1;
            while (i < data_str.len and depth > 0) {
                if (data_str[i] == '{') depth += 1;
                if (data_str[i] == '}') depth -= 1;
                i += 1;
            }
            const obj_str = data_str[obj_start..i];
            events[parsed] = try self.parseFineTuningJobEvent(obj_str);
            parsed += 1;
            search_pos = i;
        }

        return FineTuningJobEventList{
            .data = events,
            .has_more = has_more,
        };
    }

    fn parseFineTuningCheckpointList(self: *Service, response: []const u8) !FineTuningCheckpointList {
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        const data_str = self.parseJsonField(response, "data") orelse return error.ParseError;

        // Count checkpoints
        var count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, data_str, search_pos, "\"id\":")) |_| {
            count += 1;
            search_pos += 1;
        }

        var checkpoints = try self.allocator.alloc(FineTuningCheckpoint, count);
        errdefer self.allocator.free(checkpoints);

        var parsed: usize = 0;
        search_pos = 0;
        while (parsed < count) {
            const obj_start = std.mem.indexOfPos(u8, data_str, search_pos, "{") orelse break;
            var depth: u32 = 1;
            var i = obj_start + 1;
            while (i < data_str.len and depth > 0) {
                if (data_str[i] == '{') depth += 1;
                if (data_str[i] == '}') depth -= 1;
                i += 1;
            }
            const obj_str = data_str[obj_start..i];
            checkpoints[parsed] = try self.parseFineTuningCheckpoint(obj_str);
            parsed += 1;
            search_pos = i;
        }

        return FineTuningCheckpointList{
            .data = checkpoints,
            .has_more = has_more,
        };
    }

    fn parseFineTuningJobEvent(self: *Service, json_str: []const u8) !FineTuningJobEvent {
        const id = self.parseJsonField(json_str, "id") orelse "unknown";
        const created_str = self.parseJsonField(json_str, "created_at") orelse "0";
        const level = self.parseJsonField(json_str, "level") orelse "unknown";
        const message = self.parseJsonField(json_str, "message") orelse "unknown";

        return FineTuningJobEvent{
            .id = try self.allocator.dupe(u8, id),
            .created_at = std.fmt.parseInt(u64, created_str, 10) catch 0,
            .level = try self.allocator.dupe(u8, level),
            .message = try self.allocator.dupe(u8, message),
        };
    }

    fn parseFineTuningCheckpoint(self: *Service, json_str: []const u8) !FineTuningCheckpoint {
        const id = self.parseJsonField(json_str, "id") orelse "unknown";
        const created_str = self.parseJsonField(json_str, "created_at") orelse "0";
        const fine_tuned_model = self.parseJsonField(json_str, "fine_tuned_model") orelse "unknown";
        const step_number_str = self.parseJsonField(json_str, "step_number") orelse "0";
        const step_number = std.fmt.parseInt(u32, step_number_str, 10) catch 0;

        const metrics_str = self.parseJsonField(json_str, "metrics");
        const metrics: ?CheckpointMetrics = if (metrics_str) |s| try self.parseCheckpointMetrics(s) else null;

        return FineTuningCheckpoint{
            .id = try self.allocator.dupe(u8, id),
            .created_at = std.fmt.parseInt(u64, created_str, 10) catch 0,
            .fine_tuned_model = try self.allocator.dupe(u8, fine_tuned_model),
            .step_number = step_number,
            .metrics = metrics,
        };
    }

    fn parseHyperparameters(self: *Service, json_str: []const u8) !Hyperparameters {
        var hp = Hyperparameters{};

        if (self.parseJsonField(json_str, "n_epochs")) |s| {
            hp.n_epochs = std.fmt.parseInt(u32, s, 10) catch null;
        }
        if (self.parseJsonField(json_str, "batch_size")) |s| {
            hp.batch_size = std.fmt.parseInt(u32, s, 10) catch null;
        }
        if (self.parseJsonField(json_str, "learning_rate_multiplier")) |s| {
            hp.learning_rate_multiplier = std.fmt.parseFloat(f32, s) catch null;
        }
        if (self.parseJsonField(json_str, "prompt_loss_weight")) |s| {
            hp.prompt_loss_weight = std.fmt.parseFloat(f32, s) catch null;
        }

        return hp;
    }

    fn parseFineTuningJobError(self: *Service, json_str: []const u8) !FineTuningJobError {
        const code = self.parseJsonField(json_str, "code") orelse "unknown";
        const message = self.parseJsonField(json_str, "message") orelse "unknown";
        const param = self.parseJsonField(json_str, "param");

        return FineTuningJobError{
            .code = try self.allocator.dupe(u8, code),
            .message = try self.allocator.dupe(u8, message),
            .param = if (param) |v| try self.allocator.dupe(u8, v) else null,
        };
    }

    fn parseCheckpointMetrics(self: *Service, json_str: []const u8) !CheckpointMetrics {
        var metrics = CheckpointMetrics{ .step = 0 };

        if (self.parseJsonField(json_str, "step")) |s| {
            metrics.step = std.fmt.parseInt(u32, s, 10) catch 0;
        }
        if (self.parseJsonField(json_str, "train_loss")) |s| {
            metrics.train_loss = std.fmt.parseFloat(f32, s) catch null;
        }
        if (self.parseJsonField(json_str, "train_accuracy")) |s| {
            metrics.train_accuracy = std.fmt.parseFloat(f32, s) catch null;
        }
        if (self.parseJsonField(json_str, "valid_loss")) |s| {
            metrics.valid_loss = std.fmt.parseFloat(f32, s) catch null;
        }
        if (self.parseJsonField(json_str, "valid_accuracy")) |s| {
            metrics.valid_accuracy = std.fmt.parseFloat(f32, s) catch null;
        }
        if (self.parseJsonField(json_str, "full_valid_loss")) |s| {
            metrics.full_valid_loss = std.fmt.parseFloat(f32, s) catch null;
        }
        if (self.parseJsonField(json_str, "full_valid_accuracy")) |s| {
            metrics.full_valid_accuracy = std.fmt.parseFloat(f32, s) catch null;
        }

        return metrics;
    }

    fn parseStringArray(self: *Service, json_str: []const u8) ![][]const u8 {
        // Parse array of strings like ["a", "b", "c"]
        var count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, json_str, search_pos, "\"")) |_| {
            count += 1;
            search_pos += 1;
        }
        count = count / 2; // Each string has two quotes

        var arr = try self.allocator.alloc([]const u8, count);
        errdefer self.allocator.free(arr);

        var idx: usize = 0;
        search_pos = 0;
        while (idx < count) {
            const start = std.mem.indexOfPos(u8, json_str, search_pos, "\"") orelse break;
            const end = std.mem.indexOfPos(u8, json_str, start + 1, "\"") orelse break;
            arr[idx] = try self.allocator.dupe(u8, json_str[start + 1 .. end]);
            idx += 1;
            search_pos = end + 1;
        }

        return arr;
    }

    fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
        const search_pattern_len = field_name.len + 3;
        if (search_pattern_len >= 128) return null;

        var buf: [128]u8 = undefined;
        @memcpy(buf[0..field_name.len], field_name);
        buf[field_name.len] = '"';
        buf[field_name.len + 1] = ':';
        buf[field_name.len + 2] = ' ';

        const start_idx = std.mem.indexOf(u8, json_str, buf[0..search_pattern_len]) orelse return null;
        const value_start = start_idx + search_pattern_len;

        var i = value_start;
        while (i < json_str.len and (json_str[i] == ' ' or json_str[i] == '\n' or json_str[i] == '\t')) {
            i += 1;
        }

        if (i >= json_str.len) return null;

        if (json_str[i] == '"') {
            i += 1;
            const str_start = i;
            while (i < json_str.len and json_str[i] != '"') {
                if (json_str[i] == '\\') i += 1;
                i += 1;
            }
            return json_str[str_start..i];
        } else if (json_str[i] == '{' or json_str[i] == '[') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '{' or json_str[i] == '[') depth += 1;
                if (json_str[i] == '}' or json_str[i] == ']') depth -= 1;
                i += 1;
            }
            return json_str[value_start..i];
        } else {
            const num_start = i;
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E')) {
                i += 1;
            }
            return json_str[num_start..i];
        }
    }
};

// ============================================================================
// Fine-tuning Model
// ============================================================================

pub const FineTuningModel = enum {
    gpt_4o_mini,
    gpt_4o,
    gpt_3_5_turbo,

    pub fn toString(self: FineTuningModel) []const u8 {
        return switch (self) {
            .gpt_4o_mini => "gpt-4o-mini",
            .gpt_4o => "gpt-4o",
            .gpt_3_5_turbo => "gpt-3.5-turbo",
        };
    }
};

// ============================================================================
// Fine-tuning Job
// ============================================================================

pub const FineTuningJob = struct {
    id: []const u8,
    object: []const u8 = "fine_tuning.job",
    created_at: u64,
    job_error: ?FineTuningJobError = null,
    finished_at: ?u64 = null,
    hyperparameters: Hyperparameters,
    model: []const u8,
    fine_tuned_model: ?[]const u8 = null,
    organization_id: ?[]const u8 = null,
    result_files: [][]const u8,
    status: []const u8,
    trained_tokens: ?u64 = null,
    training_file: []const u8,
    validation_file: ?[]const u8 = null,
    estimated_finish: ?u64 = null,
};

// ============================================================================
// Fine-tuning Job Error
// ============================================================================

pub const FineTuningJobError = struct {
    code: []const u8,
    message: []const u8,
    param: ?[]const u8 = null,
};

// ============================================================================
// Hyperparameters
// ============================================================================

pub const Hyperparameters = struct {
    batch_size: ?u32 = null,
    learning_rate_multiplier: ?f32 = null,
    n_epochs: ?u32 = null,
    prompt_loss_weight: ?f32 = null,
};

// ============================================================================
// Fine-tuning Job List
// ============================================================================

pub const FineTuningJobList = struct {
    object: []const u8 = "list",
    data: []FineTuningJob,
    has_more: bool,
};

// ============================================================================
// Fine-tuning Job Events
// ============================================================================

pub const FineTuningJobEvent = struct {
    id: []const u8,
    object: []const u8 = "fine_tuning.job.event",
    created_at: u64,
    level: []const u8,
    message: []const u8,
};

// ============================================================================
// Fine-tuning Job Event List
// ============================================================================

pub const FineTuningJobEventList = struct {
    object: []const u8 = "list",
    data: []FineTuningJobEvent,
    has_more: bool,
};

// ============================================================================
// Fine-tuning Checkpoint
// ============================================================================

pub const FineTuningCheckpoint = struct {
    id: []const u8,
    object: []const u8 = "fine_tuning.job.checkpoint",
    created_at: u64,
    fine_tuned_model: []const u8,
    step_number: u32,
    metrics: ?CheckpointMetrics = null,
};

// ============================================================================
// Checkpoint Metrics
// ============================================================================

pub const CheckpointMetrics = struct {
    step: u32,
    train_loss: ?f32 = null,
    train_accuracy: ?f32 = null,
    valid_loss: ?f32 = null,
    valid_accuracy: ?f32 = null,
    full_valid_loss: ?f32 = null,
    full_valid_accuracy: ?f32 = null,
};

// ============================================================================
// Fine-tuning Checkpoint List
// ============================================================================

pub const FineTuningCheckpointList = struct {
    object: []const u8 = "list",
    data: []FineTuningCheckpoint,
    has_more: bool,
};

// ============================================================================
// Fine-tuning Request Params
// ============================================================================

pub const FineTuningJobParams = struct {
    training_file: []const u8,
    model: ?[]const u8 = null,
    validation_file: ?[]const u8 = null,
    hyperparameters: ?Hyperparameters = null,
    seed: ?u32 = null,
    suffix: ?[]const u8 = null,
};

// ============================================================================
// Fine-tuning Method Types (DPO, Reinforcement, Supervised)
// ============================================================================

/// Fine-tuning method type
pub const FineTuningMethod = enum {
    supervised,
    dpo,
    reinforcement,
};

/// DPO (Direct Preference Optimization) method parameters
pub const DpoMethod = struct {
    reward_model: []const u8,
};

/// DPO hyperparameters
pub const DpoHyperparameters = struct {
    n_epochs: ?u32 = null,
    affinity_similarity_strength: ?f32 = null,
    batch_size: ?u32 = null,
    beta: ?f32 = null,
    learning_rate_multiplier: ?f32 = null,
    margin_threshold: ?f32 = null,
    mini_batch_size: ?u32 = null,
    reps: ?u32 = null,
};

/// Reinforcement learning method parameters
pub const ReinforcementMethod = struct {
    reward_model: []const u8,
};

/// Reinforcement hyperparameters
pub const ReinforcementHyperparameters = struct {
    n_epochs: ?u32 = null,
    batch_size: ?u32 = null,
    learning_rate: ?f32 = null,
    gradient_accumulation_steps: ?u32 = null,
};

/// Supervised method parameters
pub const SupervisedMethod = struct {
    hyperparams: Hyperparameters,
};

/// DPO fine-tuning job creation parameters
pub const DpoFineTuningJobParams = struct {
    model: []const u8,
    method: DpoMethod,
    hyperparameters: ?DpoHyperparameters = null,
    suffix: ?[]const u8 = null,
};

/// Reinforcement fine-tuning job creation parameters
pub const ReinforcementFineTuningJobParams = struct {
    model: []const u8,
    method: ReinforcementMethod,
    hyperparameters: ?ReinforcementHyperparameters = null,
    suffix: ?[]const u8 = null,
};

/// Supervised fine-tuning job creation parameters
pub const SupervisedFineTuningJobParams = struct {
    model: []const u8,
    method: SupervisedMethod,
    hyperparameters: ?Hyperparameters = null,
    suffix: ?[]const u8 = null,
};
