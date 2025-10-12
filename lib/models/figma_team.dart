// lib/models/figma_team.dart

import 'figma_project.dart';

class FigmaTeam {
  final String id;
  final String name;
  final List<FigmaProject> projects;

  FigmaTeam({
    required this.id,
    required this.name,
    required this.projects,
  });
}