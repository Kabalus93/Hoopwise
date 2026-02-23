import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SessionData {
  title: string;
  sessionType: string;
  durationMinutes: number;
  description: string;
  dayOfWeek: string;
  weekNumber: number;
  objectives: string[];
  warmupDrills: string[];
  mainDrills: string[];
  cooldownActivities: string[];
}

interface PhaseData {
  title: string;
  focus: string[];
  durationWeeks: number;
  description: string;
  objectives: string[];
  sessions: SessionData[];
}

interface ProgramPhasesResponse {
  phases: PhaseData[];
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { prompt, ageGroup, skillLevel, durationWeeks } = await req.json();

    const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
    if (!GROQ_API_KEY) {
      throw new Error("GROQ_API_KEY not configured");
    }

    const systemPrompt = `You are an expert European youth basketball coach and training program designer with deep knowledge of:
- FIBA Europe youth development guidelines
- Age-appropriate skill progressions for youth players
- Periodization and training phase planning
- Modern basketball coaching methodologies

Your task is to generate detailed, practical training phases and sessions that follow European basketball federation standards.

IMPORTANT GUIDELINES FOR EACH AGE GROUP:

U8 (Mini Basketball):
- Focus: Fun, basic motor skills, ball familiarity
- Court: Mini court, lower basket (2.6m)
- Ball: Size 5
- Sessions: 45-60 min max
- Key skills: Dribbling with both hands, basic catches, stationary shooting form

U10:
- Focus: Fundamental movement, basic basketball skills
- Court: Mini court transitioning to half court
- Ball: Size 5
- Sessions: 60 min
- Key skills: Layups, passing (chest, bounce), defensive stance

U12:
- Focus: Individual skill development, 1v1, 2v2
- Court: Full court introduction
- Ball: Size 5-6
- Sessions: 60-75 min
- Key skills: Jump stops, pivoting, shooting form, help defense concepts

U14:
- Focus: Position-less basketball, team concepts
- Court: Full court
- Ball: Size 6-7
- Sessions: 75-90 min
- Key skills: Pick and roll basics, zone defense, free throw routine

U16:
- Focus: Position specialization begins, advanced tactics
- Court: Full court
- Ball: Size 7
- Sessions: 90 min
- Key skills: Advanced footwork, reading defenses, transition play

U18/Senior:
- Focus: Game preparation, tactical mastery
- Court: Full court
- Ball: Size 7
- Sessions: 90-120 min
- Key skills: Game film analysis, situational plays, mental preparation

SESSION STRUCTURE (adapt times to age):
1. Warm-up (10-15%): Dynamic stretching, ball handling
2. Skill work (30-40%): Technical drills
3. Game-based learning (30-40%): Small-sided games, scrimmages
4. Cool-down (10%): Static stretching, recap

Always include:
- Specific drill names and descriptions
- Time allocations
- Progressions within and between sessions
- Age-appropriate language and expectations`;

    const userPrompt = `${prompt}

Generate a structured JSON response with training phases for a ${durationWeeks}-week program.

Return ONLY valid JSON in this exact format:
{
  "phases": [
    {
      "title": "Phase name (e.g., Foundation, Development, Competition)",
      "focus": ["skill1", "skill2"],
      "durationWeeks": number,
      "description": "Detailed phase description",
      "objectives": ["objective1", "objective2", "objective3"],
      "sessions": [
        {
          "title": "Session title",
          "sessionType": "practice",
          "durationMinutes": 60,
          "description": "Session overview",
          "dayOfWeek": "monday",
          "weekNumber": 1,
          "objectives": ["session objective 1", "session objective 2"],
          "warmupDrills": ["drill1", "drill2"],
          "mainDrills": ["drill1 with description", "drill2 with description"],
          "cooldownActivities": ["activity1", "activity2"]
        }
      ]
    }
  ]
}

Focus areas should use lowercase single words like: shooting, passing, dribbling, defense, rebounding, conditioning, fundamentals, teamwork, positioning, footwork

Create ${Math.ceil(durationWeeks / 6)} to ${Math.ceil(durationWeeks / 4)} phases with appropriate sessions for each phase.
Each phase should have 2-4 sessions per week of training.
Make drill descriptions specific and actionable.`;

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${GROQ_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.7,
        max_tokens: 8000,
        response_format: { type: "json_object" },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Groq API error:", errorText);
      throw new Error(`Groq API error: ${response.status}`);
    }

    const data = await response.json();
    const content = data.choices[0]?.message?.content;

    if (!content) {
      throw new Error("No content in response");
    }

    let parsedResponse: ProgramPhasesResponse;
    try {
      parsedResponse = JSON.parse(content);
    } catch (parseError) {
      console.error("Failed to parse response:", content);
      throw new Error("Invalid JSON response from AI");
    }

    // Validate response structure
    if (!parsedResponse.phases || !Array.isArray(parsedResponse.phases)) {
      throw new Error("Invalid response structure: missing phases array");
    }

    // Ensure each phase has required fields
    for (const phase of parsedResponse.phases) {
      if (!phase.title || !phase.sessions) {
        throw new Error("Invalid phase structure");
      }
      // Ensure focus is an array
      if (!Array.isArray(phase.focus)) {
        phase.focus = ["fundamentals"];
      }
      // Ensure sessions have required fields
      for (const session of phase.sessions) {
        if (!session.title) {
          session.title = "Training Session";
        }
        if (!session.sessionType) {
          session.sessionType = "practice";
        }
        if (!session.durationMinutes) {
          session.durationMinutes = 60;
        }
      }
    }

    return new Response(JSON.stringify(parsedResponse), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Failed to generate program phases" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
