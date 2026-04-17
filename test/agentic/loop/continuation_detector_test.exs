defmodule Agentic.Loop.ContinuationDetectorTest do
  use ExUnit.Case, async: true

  alias Agentic.Loop.ContinuationDetector

  describe "step completion detection" do
    test "detects 'Step 1 is complete'" do
      assert ContinuationDetector.step_complete?("Step 1 is complete. Moving on.")
    end

    test "detects 'Completed step 2'" do
      assert ContinuationDetector.step_complete?("Completed step 2 successfully.")
    end

    test "detects checkmark pattern" do
      assert ContinuationDetector.step_complete?("✓ Step 3 done")
    end

    test "returns false for no step" do
      refute ContinuationDetector.step_complete?("Working on the task")
    end

    test "extract_step_number returns step number" do
      assert ContinuationDetector.extract_step_number("Step 3 is complete") == 3
      assert ContinuationDetector.extract_step_number("Completed step 5") == 5
      assert ContinuationDetector.extract_step_number("No step here") == nil
    end
  end

  describe "task completion detection" do
    test "detects 'All done'" do
      assert ContinuationDetector.task_complete?("All done.")
    end

    test "detects 'Nothing more to do'" do
      assert ContinuationDetector.task_complete?("Nothing more to do here.")
    end

    test "detects 'Task is complete'" do
      assert ContinuationDetector.task_complete?("Task is complete")
    end

    test "returns false for ongoing work" do
      refute ContinuationDetector.task_complete?("Still working on it")
    end
  end

  describe "blocker detection" do
    test "detects 'I can't proceed'" do
      assert ContinuationDetector.blocked?("I can't proceed without more info.")
    end

    test "detects 'I need clarification'" do
      assert ContinuationDetector.blocked?("I need clarification on this requirement.")
    end

    test "returns false when no blocker" do
      refute ContinuationDetector.blocked?("Everything is going well")
    end
  end

  describe "detect/2" do
    test "returns empty for nil" do
      assert ContinuationDetector.detect(nil) == []
    end

    test "returns empty for empty string" do
      assert ContinuationDetector.detect("") == []
    end

    test "returns multiple detections" do
      text = "Step 1 is complete. To summarize, we fixed the bug."

      results = ContinuationDetector.detect(text)
      categories = Enum.map(results, & &1.category)
      assert :step_complete in categories
      assert :summary in categories
    end

    test "detections have confidence values" do
      results = ContinuationDetector.detect("Step 1 is complete.")
      assert Enum.all?(results, &(&1.confidence > 0 and &1.confidence <= 1.0))
    end

    test "detections are sorted by confidence descending" do
      results = ContinuationDetector.detect("Step 1 is complete. I can't proceed.")

      if length(results) > 1 do
        confidences = Enum.map(results, & &1.confidence)
        assert confidences == Enum.sort(confidences, :desc)
      end
    end

    test "suppresses step detection with steps: false" do
      results = ContinuationDetector.detect("Step 1 is complete.", steps: false)
      refute Enum.any?(results, &(&1.category == :step_complete))
    end
  end

  describe "false positive filtering" do
    test "does not detect completion in questions ending with ?" do
      refute ContinuationDetector.task_complete?("Is everything done?")
    end

    test "detects completion in declarative statements" do
      assert ContinuationDetector.task_complete?("Everything is done.")
    end
  end
end
