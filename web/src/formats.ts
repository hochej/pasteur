const aliases: Record<string, string> = {
  cif: 'mmcif',
  mmcif: 'mmcif',
  pdbqt: 'pdb',
  mol: 'mol',
  mol2: 'mol2',
  sdf: 'sdf',
  xyz: 'xyz',
  pdb: 'pdb',
  gro: 'gro',
  smiles: 'xyz',  // Converted to XYZ in Swift
  smi: 'xyz'
};

export function normalizeFormat(format: string): string {
  const key = format.toLowerCase();
  return aliases[key] ?? key;
}
