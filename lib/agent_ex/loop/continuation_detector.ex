defmodule AgentEx.Loop.ContinuationDetector do
  @moduledoc """
  Detects plan steps and completion signals in LLM text output.

  Ported from Homunculus ContinuationDetector. Uses regex patterns to detect
  when the agent signals step completion or task completion.

  ## Detection Categories

  1. **Step completion** — "Step 1 is complete", "Completed step 2"
  2. **Task completion** — "All done", "Task finished", "Nothing left to do"
  3. **Continuation intent** — "Let me continue", "Moving on to"
  4. **Blockers** — "I can't proceed", "I need clarification"
  5. **Summary signals** — "In summary", "To summarize"
  """

  @step_complete_patterns [
    ~r/step\s+\d+\s+(?:is\s+)?(?:complete|done|finished)/i,
    ~r/(?:completed|finished|done with)\s+step\s+\d+/i,
    ~r/✓.*step\s+\d+/i
  ]

  @task_complete_patterns [
    ~r/\b(?:all\s+)?(?:done|finished|complete)\b(?:\s+(?:with\s+)?(?:the\s+)?(?:task|work|job|assignment))?/i,
    ~r/nothing\s+(?:more|left|else)\s+to\s+do/i,
    ~r/task\s+(?:is\s+)?(?:complete|finished|done)/i,
    ~r/(?:have|I've)\s+(?:successfully\s+)?(?:completed|finished|done)/i
  ]

  @continuation_patterns [
    ~r/(?:let me|I'll|I will)\s+(?:continue|move on|proceed|now)/i,
    ~r/moving\s+on\s+to/i,
    ~r/next,?\s+(?:I|let me|we)/i,
    ~r/now\s+(?:I|let me|we)\s+(?:need|will|can|should)/i
  ]

  @blocker_patterns [
    ~r/I\s+(?:can't|cannot|am unable to)\s+(?:proceed|continue|move forward)/i,
    ~r/I\s+need\s+(?:more\s+)?(?:clarification|information|input|details)/i,
    ~r/(?:blocked|stuck|unsure)\s+(?:on|about|how)/i,
    ~r/(?:please\s+)?(?:clarify|confirm|let me know)/i
  ]

  @summary_patterns [
    ~r/in\s+summary,?/i,
    ~r/to\s+summarize,?/i,
    ~r/(?:here's|here is)\s+(?:a\s+)?(?:summary|recap|overview)/i,
    ~r/briefly,?\s+(?:what|the|I)/i
  ]

  @type detection :: %{
          category: :step_complete | :task_complete | :continuation | :blocker | :summary,
          match: String.t(),
          confidence: float()
        }

  @doc """
  Detect continuation signals in text. Returns a list of detections sorted
  by confidence (highest first). Pass `steps: false` to suppress step detection.
  """
  @spec detect(String.t(), keyword()) :: [detection()]
  def detect(text, opts \\ [])

  def detect(nil, _opts), do: []
  def detect("", _opts), do: []

  def detect(text, opts) do
    detect_steps = Keyword.get(opts, :steps, true)

    detections =
      []
      |> maybe_detect_steps(text, detect_steps)
      |> detect_category(text, :task_complete, @task_complete_patterns, 0.85)
      |> detect_category(text, :continuation, @continuation_patterns, 0.7)
      |> detect_category(text, :blocker, @blocker_patterns, 0.8)
      |> detect_category(text, :summary, @summary_patterns, 0.6)

    detections
    |> Enum.sort_by(&(-&1.confidence))
    |> Enum.uniq_by(& &1.category)
  end

  @doc "Returns true if any step completion is detected."
  @spec step_complete?(String.t()) :: boolean()
  def step_complete?(nil), do: false
  def step_complete?(text), do: Enum.any?(@step_complete_patterns, &Regex.match?(&1, text))

  @doc "Returns true if task completion is detected."
  @spec task_complete?(String.t()) :: boolean()
  def task_complete?(nil), do: false

  def task_complete?(text) do
    if text =~ ~r/\?\s*$/ do
      false
    else
      Enum.any?(@task_complete_patterns, &Regex.match?(&1, text))
    end
  end

  @doc "Returns true if a blocker is detected."
  @spec blocked?(String.t()) :: boolean()
  def blocked?(nil), do: false
  def blocked?(text), do: Enum.any?(@blocker_patterns, &Regex.match?(&1, text))

  @doc "Extract the first step number mentioned as complete."
  @spec extract_step_number(String.t()) :: integer() | nil
  def extract_step_number(nil), do: nil

  def extract_step_number(text) do
    patterns = [
      ~r/step\s+(\d+)\s+(?:is\s+)?(?:complete|done|finished)/i,
      ~r/(?:completed|finished|done with)\s+step\s+(\d+)/i,
      ~r/✓.*step\s+(\d+)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, num] -> String.to_integer(num)
        _ -> nil
      end
    end)
  end

  defp maybe_detect_steps(detections, text, true) do
    detect_category(detections, text, :step_complete, @step_complete_patterns, 0.9)
  end

  defp maybe_detect_steps(detections, _text, false), do: detections

  defp detect_category(detections, text, category, patterns, base_confidence) do
    case find_match(text, patterns) do
      nil ->
        detections

      match ->
        confidence = adjust_confidence(base_confidence, text, match)
        [%{category: category, match: match, confidence: confidence} | detections]
    end
  end

  defp find_match(text, patterns) do
    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [match | _] -> match
        _ -> nil
      end
    end)
  end

  defp adjust_confidence(base, text, match) do
    match_len = String.length(match)
    text_len = String.length(text)

    position_boost =
      if text_len > 0 and match_len > 0 do
        pos = String.split(text, match) |> hd() |> String.length()
        if pos < text_len * 0.3, do: 0.05, else: 0.0
      else
        0.0
      end

    min(base + position_boost, 1.0)
  end
end
