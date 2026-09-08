package main

import (
	"reflect"
	"testing"
)

func strPtr(s string) *string { return &s }

func TestParseExtractedSymptomsValid(t *testing.T) {
	content := `{"symptoms": [{"type": "nausea", "date_ref": "today"}, {"type": "fatigue", "date_ref": "yesterday"}]}`
	got := parseExtractedSymptoms(content)
	want := []symptomItem{
		{Type: "nausea", DateRef: strPtr("today")},
		{Type: "fatigue", DateRef: strPtr("yesterday")},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestParseExtractedSymptomsEmpty(t *testing.T) {
	if got := parseExtractedSymptoms(`{"symptoms": []}`); len(got) != 0 {
		t.Fatalf("expected empty, got %+v", got)
	}
}

func TestParseExtractedSymptomsMalformed(t *testing.T) {
	if got := parseExtractedSymptoms("not json"); len(got) != 0 {
		t.Fatalf("expected empty, got %+v", got)
	}
	if got := parseExtractedSymptoms(`{"symptoms": "nope"}`); len(got) != 0 {
		t.Fatalf("expected empty, got %+v", got)
	}
}

func TestParseExtractedSymptomsCleansFence(t *testing.T) {
	content := "```json\n{\"symptoms\": [{\"type\": \"headache\", \"date_ref\": null}]}\n```"
	got := parseExtractedSymptoms(content)
	want := []symptomItem{{Type: "headache", DateRef: nil}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestParseExtractedSymptomsFiltersUnknown(t *testing.T) {
	content := `{"symptoms": [{"type": "nausea", "date_ref": "today"}, {"type": "teleportation", "date_ref": null}]}`
	got := parseExtractedSymptoms(content)
	want := []symptomItem{{Type: "nausea", DateRef: strPtr("today")}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}
