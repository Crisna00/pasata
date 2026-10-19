package main

import "testing"

func TestRecommendationMessage(t *testing.T) {
	if got := recommendationMessage(0); got == "" {
		t.Fatal("empty recommendation message")
	}
	if got := recommendationMessage(2); got != "Ditemukan 2 kandidat. Periksa rekomendasi dan konfirmasi sebelum penempatan." {
		t.Fatalf("unexpected message: %q", got)
	}
}

func TestRound2(t *testing.T) {
	cases := []struct{ in, want float64 }{{12.345, 12.35}, {0, 0}, {4.1, 4.1}}
	for _, c := range cases {
		if got := round2(c.in); got != c.want {
			t.Errorf("round2(%v)=%v want %v", c.in, got, c.want)
		}
	}
}
